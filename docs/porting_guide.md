# Antminer S19J Control Board v2.5 — BSP Porting Guide
# Buildroot 2025.02 + Linux Kernel 6.6.58 on TI AM335x

> **Comprehensive technical documentation covering the porting process, root-cause diagnostics, hardware quirks, and solutions.**

---

## 1. Hardware Overview

| Component | Details |
|-----------|---------|
| **Board Model** | Antminer S19J Control Board v2.5 |
| **SoC** | TI AM335x (AM3352 ARMv7 Cortex-A8) |
| **RAM** | 256 MB DDR3 |
| **Storage** | 128 MB NAND (Micron MT29F1G08ABAEAWP) |
| **Stock Bootloader** | U-Boot 2013.04-dirty (Jan 04 2015) — located in NAND |
| **Ethernet PHY** | SMSC LAN8710/LAN8720 |
| **Serial Console** | UART0 at 0x44e09000 (115200 8N1) |
| **Stock OS** | Angstrom Linux 3.8.13 (in NAND) |

---

## 2. Project Goals

Boot **Linux Kernel 6.6.58** + **Buildroot 2025.02** directly from an SD Card while:
- ❌ **NOT flashing NAND** — keeping factory firmware untouched
- ❌ **NOT upgrading bootloader** — reusing stock NAND U-Boot 2013.04
- ✅ Packaging into a single **`sdcard.img`** flashable with BalenaEtcher / `dd`

---

## 3. Directory Layout

```text
antminer-s19j-bsp/
├── README.md                           # Main Documentation
├── .gitignore                          # Git ignore rules for build artifacts
├── board/
│   └── bitmain/
│       └── antminer-s19j/
│           ├── am335x-antminer.dts     # Custom Device Tree for Antminer S19J v2.5
│           ├── uEnv.txt                # U-Boot Auto-boot file for SD Card
│           └── boot.cmd                # U-Boot boot script source
├── configs/
│   └── antminer_s19j_defconfig        # Buildroot Defconfig (Linux 6.6 + Dropbear SSH)
├── docs/
│   └── porting_guide.md                # Comprehensive BSP Porting Guide
└── scripts/
    └── build.sh                        # One-click build script for Ubuntu / WSL
```

---

## 4. Key Challenges & Technical Solutions

---

### 4.1. Host Tooling Build Failure (GCC 14/15 C23 Gnulib Incompatibility)

> [!CAUTION]
> GCC 14+ defaults to C23 mode, breaking older `gnulib` headers (m4 1.4.19, gmp 6.3.0) due to syntax collisions with `[[nodiscard]]`.

**Symptom:**
```text
error: expected identifier or '(' before 'int'
  gl_list.h: _GL_ATTRIBUTE_NODISCARD
```

**Root Cause:** Modern host Linux distributions (Ubuntu 24.04+ / 26.04) ship with GCC 14/15. Buildroot 2025.02 host tools use older `gnulib` releases that fail under C23 strict syntax checks.

**Solution:** Patch `package/Makefile.in` to enforce `-std=gnu17` for all host package compilations:

```diff
- HOST_CFLAGS = -O2 ...
+ HOST_CFLAGS = -O2 -std=gnu17 ...
```

This workaround is integrated into [`scripts/build.sh`](../scripts/build.sh).

---

### 4.2. Kernel 6.6 DTS Directory Hierarchy Restructure

**Symptom:**
```text
fatal error: am335x-boneblack.dts: No such file or directory
```

**Root Cause:** 
- Linux ≤ 5.x: `arch/arm/boot/dts/am335x-boneblack.dts`
- Linux ≥ 6.x: `arch/arm/boot/dts/ti/omap/am335x-boneblack.dts`

**Solution:**
1. Place custom DTS file at `arch/arm/boot/dts/ti/omap/am335x-antminer.dts`.
2. Use relative inclusion `#include "am335x-boneblack.dts"`.
3. Set Buildroot defconfig:
```ini
BR2_LINUX_KERNEL_INTREE_DTS_NAME="ti/omap/am335x-antminer"
```

---

### 4.3. Kernel Panic: External Abort on PRU-ICSS (0x4a326000)

> [!CAUTION]
> Critical hardware crash during early driver initialization.

**Symptom:**
```text
[    1.902274] Unhandled fault: external abort on non-linefetch (0x1008) at 0xd03e6000
[    1.946548] PC is at sysc_probe+0xbb8/0x13cc
```

**Root Cause:**
- Physical address `0x4a326000` corresponds to the PRU-ICSS SYSCONFIG register.
- On Antminer control boards, the PRU block is unclocked and unpowered.
- In Linux 6.6, the `ti-sysc` interconnect driver probes `target-module@30000` (`&pruss_tm`).
- Accessing `0x4a326000` while unclocked triggers an **L3 Interconnect External Abort**.

**Solution — Disable both PRU core & Interconnect Target Module in DTS:**

```dts
/* Disable PRU core driver */
&pruss {
    status = "disabled";
};

/* CRITICAL: Disable PRU Interconnect Target Module wrapper
 * Disabling &pruss alone is INSUFFICIENT because ti-sysc still probes &pruss_tm. */
&pruss_tm {
    status = "disabled";
};

/* Disable LCD Controller (not present on hardware) */
&lcdc {
    status = "disabled";
};
```

---

### 4.4. Stock Bitmain U-Boot 2013.04 Boot Sequence Analysis

**Boot Order (Observed from UART logs):**

```text
1. gpio pin 53 -> Checks SD card insertion
2. gpio pin 54 -> Attempts ext2 mount on Partition 1
   -> "Failed to mount ext2 filesystem..."
   -> Fallback to fatload for uEnv.txt
3. gpio pin 55 -> Searches for /boot/uImage or executes uenvcmd
4. gpio pin 56 -> Searches for /boot/am335x-boneblack.dtb
5. Fallback      -> Boots legacy image from NAND Flash
```

**Key Findings:**

| Behavior | Details |
|----------|---------|
| `uEnv.txt` Parsing | Loaded via `fatload` from Partition 1 |
| Default DTB Search | `/boot/am335x-boneblack.dtb` (Long VFAT name) |
| Kernel Command | Supports `bootz` (zImage) and `bootm` (uImage) |
| Filesystem Support | FAT32 with Long Filenames supported; EXT2/4 on boot partition unsupported |

---

### 4.5. FAT16 Short Filename Limitation

**Symptom:**
```text
** File not found /boot/am335x-boneblack.dtb **
```

**Root Cause:** Standard FAT16 formatting scripts created 8.3 short names, truncating long paths required by stock U-Boot.

**Solution:** Use `mtools` (`mkfs.fat -F 32` + `mcopy`) to build a proper FAT32 partition with VFAT Long Filename (LFN) entries:

```bash
mkfs.fat -F 32 -n 'BOOT' boot.vfat
mmd -i boot.vfat ::/boot
mcopy -o -i boot.vfat am335x-antminer.dtb ::/am335x-boneblack.dtb
mcopy -o -i boot.vfat am335x-antminer.dtb ::/boot/am335x-boneblack.dtb
```

---

### 4.6. Serial Console Renaming: ttyO0 -> ttyS0

**Symptom:**
```text
can't open /dev/ttyO0: No such file or directory
```

**Root Cause:**
- Linux 6.6 replaces the legacy `omap-serial` driver (`/dev/ttyO0`) with `8250_omap` (`/dev/ttyS0`).
- Busybox `init` failed when trying to spawn `getty` on non-existent `/dev/ttyO0`.

**Solution:** Update serial port configurations across all files to `ttyS0`:
1. `uEnv.txt`: `console=ttyS0,115200n8`
2. `am335x-antminer.dts`: `stdout-path = "serial0:115200n8"`
3. `inittab`: Spawn terminal on `ttyS0`
4. `/etc/init.d/rcS`: Create `/dev/ttyO0` node at runtime for backward compatibility:
   ```sh
   mknod /dev/ttyO0 c 4 64 2>/dev/null || ln -sf /dev/ttyS0 /dev/ttyO0
   ```

---

### 4.7. UART0 eDMA Buffering vs Terminal Unresponsiveness

**Symptom:**
Keyboard inputs typed in PuTTY were ignored after Linux kernel booted, even though the ESC key worked in U-Boot.

**Root Cause:**
- Kernel config `CONFIG_SERIAL_8250_DMA=y` enabled eDMA channel 27 for UART0 RX.
- eDMA buffers incoming serial bytes and only fires interrupts when full buffers are received. Single keystrokes from terminal clients remained trapped in DMA buffers without reaching Linux TTY line discipline.

**Solution:** Disable DMA on `&uart0` in Device Tree to force interrupt-driven PIO mode:

```dts
&uart0 {
    pinctrl-names = "default";
    pinctrl-0 = <&uart0_pins>;
    status = "okay";
    /* Disable eDMA for UART0 to ensure immediate PIO keystroke delivery */
    /delete-property/ dmas;
    /delete-property/ dma-names;
};
```

---

### 4.8. UART Hardware Flow Control (CRTSCTS) Blocking

**Symptom:**
Terminal spawned by `getty` blocked input because RTS/CTS signals were disconnected on 3-pin USB-to-UART TTL adapters (TX/RX/GND).

**Solution:** Bypass `getty` flow control initialization by spawning direct root shell in `/etc/inittab`:

```ini
ttyS0::respawn:-/bin/sh
```

---

## 5. Final SD Card Image Structure (`sdcard.img`)

```text
sdcard.img (133 MB)
├── MBR Partition Table (DOS)
├── Partition 1: FAT32 (32 MB, offset 1 MiB)
│   ├── zImage                    # Linux 6.6.58 Kernel Image
│   ├── uImage                    # Legacy U-Boot Kernel Image
│   ├── uEnv.txt                  # Boot Environment
│   ├── boot.scr                  # Compiled Boot Script
│   └── am335x-boneblack.dtb      # Device Tree Blob (PRUSS disabled, PIO UART)
└── Partition 2: EXT4 (100 MB, offset 33 MiB)
    └── Root Filesystem
        ├── /etc/inittab          # Direct root shell on ttyS0
        ├── /etc/init.d/S50dropbear # Dropbear SSH Daemon
        ├── /etc/network/interfaces # Auto DHCP on eth0
        └── /usr/sbin/dropbear    # SSH Server Binary
```

---

## 6. Verification & Access

```text
Welcome to Buildroot on Antminer S19J v2.5
antminer-s19j login: root
Password: root
# uname -a
Linux antminer-s19j 6.6.58 #1 SMP ARMv7
```

**SSH Access:**
```bash
ssh root@192.168.1.230
# Password: root
```

---

## 7. Lessons Learned Summary

1. **Interconnect Probing (`ti-sysc`):** Always disable both core devices (`&pruss`) and target wrappers (`&pruss_tm`) when hardware blocks are unclocked.
2. **UART eDMA:** Disable DMA on debug UART interfaces (`/delete-property/ dmas`) to avoid single-keystroke buffering delays.
3. **Partition Mirroring:** Ensure both FAT32 boot and EXT4 rootfs partitions are rewritten to `sdcard.img` after any file edits.
4. **Runtime Devtmpfs:** Static node symlinks in rootfs image are masked by `devtmpfs`; create compatibility nodes in `/etc/init.d/rcS`.
