# Antminer S19J Control Board v2.5 (AM335x) — Buildroot BSP & Linux 6.6 Port

Full Board Support Package (BSP) and comprehensive documentation for porting modern **Linux Kernel 6.6.58** and **Buildroot 2025.02** to the **Antminer S19J Control Board v2.5** (TI AM335x) via SD Card — leaving the original NAND Flash, SPL, and stock U-Boot 2013.04 untouched and completely safe.

---

## 📁 Repository Structure

```text
antminer-s19j-bsp/
├── README.md                           # Main Documentation
├── .gitignore                          # Git ignore rules for build artifacts
├── board/
│   └── bitmain/
│       └── antminer-s19j/
│           ├── am335x-antminer.dts     # Custom Device Tree (PRUSS/LCDC disabled, UART0 PIO)
│           ├── uEnv.txt                # U-Boot Auto-boot file for SD Card
│           └── boot.cmd                # U-Boot boot script source
├── configs/
│   └── antminer_s19j_defconfig        # Buildroot Defconfig (Linux 6.6 + Dropbear SSH)
├── docs/
│   └── porting_guide.md                # Comprehensive BSP Porting Guide & Troubleshooting
└── scripts/
    └── build.sh                        # One-click build script for Ubuntu / WSL
```

---

## 🚀 Quick Start (Building on Ubuntu / WSL)

1. Clone this repository:
   ```bash
   git clone <repo_url> antminer-s19j-bsp
   cd antminer-s19j-bsp
   chmod +x scripts/build.sh
   ./scripts/build.sh
   ```

2. Flashing to SD Card using `sdcard.img` (BalenaEtcher / Rufus / `dd`):
   ```bash
   # Flash sdcard.img directly to your SD card device (e.g. /dev/sdX)
   sudo dd if=images/sdcard.img of=/dev/sdX bs=4M status=progress conv=fsync
   ```

---

## 🔑 Login & Access Credentials

| Service | Access Details |
|---------|----------------|
| **Serial Console** | UART0 (115200 8N1), direct root shell on `ttyS0` |
| **SSH Server** | `ssh root@<BOARD_IP>` (Port 22, Dropbear) |
| **Root Password** | `root` |
| **Network** | Automatic DHCP on `eth0` |

---

## 🔑 Key Engineering Discoveries & Solutions

1. **PRU-ICSS External Abort Panic (0x4a326000):**
   - Disabling `&pruss` **and** interconnect target module `&pruss_tm` in `am335x-antminer.dts` prevents `ti-sysc` from probing unclocked PRU hardware.

2. **UART0 DMA vs Terminal Unresponsiveness:**
   - Removing `dmas` and `dma-names` from `&uart0` in DTS forces PIO mode (interrupt-driven), immediately delivering single keypresses from PuTTY / terminal without trapping data in eDMA buffers.

3. **Serial Naming (Linux 6.6):**
   - AM335x UART0 is exposed as `/dev/ttyS0` (8250_omap driver). A runtime device node `/dev/ttyO0` is created in `/etc/init.d/rcS` for backward compatibility.

4. **Dropbear SSH & Auto-DHCP:**
   - Pre-configured Dropbear SSH daemon and background DHCP client on `eth0`.

---

## 📜 Full Porting Documentation

For complete technical details, step-by-step problem resolutions, and boot sequence analysis, read [`docs/porting_guide.md`](docs/porting_guide.md).

---

## 📜 License
MIT License / GPLv2.
