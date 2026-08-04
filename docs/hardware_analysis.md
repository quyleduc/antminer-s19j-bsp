# Antminer S19J Control Board v2.5 Hardware & BSP Analysis Report

## 1. Hardware Specifications

| Component | Specification | Description / Notes |
| :--- | :--- | :--- |
| **SoC** | TI AM335x | ARM Cortex-A8 @ 600-800 MHz |
| **RAM** | 256 MB DDR3 | Physical address: `0x80000000` - `0x90000000` |
| **NAND Flash** | 128 MB | OMAP2 NAND (2KB Page, 128KB Erase Block) |
| **Bootloader** | U-Boot 2013.04-dirty | Bitmain customized build (Jan 04 2015) |
| **Ethernet** | CPSW + SMSC LAN8710/8720 | RMII Mode, PHY ADDR = 0 |
| **UART0** | `0x44e09000` | Debug Console (ttyO0 / ttyS0 @ 115200 8N1) |

---

## 2. Memory Layout & Boot Addresses

```text
DRAM Start: 0x80000000

0x80008000  <-- Kernel zImage load address (32KB offset for ARM Page Tables)
0x81000000  <-- Initrd / Ramdisk address
0x88000000  <-- FDT / Device Tree Blob (dtb) address
```

---

## 3. Crash Root Cause Analysis (`0x4a326000 External Abort`)

### Symptom:
When booting modern Linux Kernel 6.6 using standard BeagleBone Black DTB (`am335x-boneblack.dtb`), the kernel hangs or crashes at **5.37s**:
```text
[ 5.375967] Unhandled fault: external abort on non-linefetch (0x1008) at 0xd0366000
[ 5.417725] PC is at sysc_probe+0xc5c/0x142c
Stack trace target: 0x4a326000
```

### Technical Explanation:
1. Physical address `0x4a326000` belongs to the **PRU-ICSS** (Programmable Real-Time Unit Subsystem) on TI AM335x.
2. On BeagleBone Black, PRU-ICSS (`pruss@4a300000`), LCD Controller (`lcdc`), and HDMI Framer (`tda19988`) are enabled.
3. On the Antminer S19J Control Board v2.5, Bitmain **disables the power & clock domains** for PRUSS and LCDC.
4. When Linux 6.6 initializes the Interconnect driver (`sysc_probe`) and reads MMIO registers at `0x4a326000`, the unclocked bus triggers an **L3 Interconnect External Abort (0x1008)**, resulting in an unrecoverable kernel panic.

### Fix:
Disabling `pruss`, `lcdc`, and `hdmi` in the custom Device Tree `am335x-antminer.dts` completely eliminates the fault and allows clean boot into Buildroot rootfs.
