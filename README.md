# Antminer S19J v2.5 — Buildroot Linux BSP

Experimental, non-destructive SD-boot BSP for TI AM335x. Based on Buildroot 2025.02 and Linux 6.6.58. **Not a BeagleBone Black hardware-compatible board.**

## Status
- Original NAND bootloader remains untouched by the scripts.
- Custom DTS retains PRU-ICSS disabled to avoid a previously observed external abort.
- UART0 DMA is disabled in DTS for reliable serial input.
- SD image packaging is implemented, but **a clean build and hardware boot have not been verified on this branch**.
- Do not enable unverified BBB peripherals or overwrite NAND.

## Build (Ubuntu / WSL Linux filesystem)
```bash
git clone https://github.com/quyleduc/antminer-s19j-bsp.git
cd antminer-s19j-bsp
bash scripts/validate.sh
bash scripts/build.sh
```

Output is expected at `buildroot-2025.02/output/images/sdcard.img` after a successful build. Requires standard Buildroot dependencies including make, gcc, g++, bc, cpio, rsync, unzip, Python, OpenSSL headers, ncurses, wget and tar. A new build can take significant time and disk space.

The script preserves an existing Buildroot `.config`. Set `RESET_CONFIG=1` to regenerate from the tracked defconfig. Use `JOBS=4` to limit parallel jobs. Host GCC compatibility is **not guaranteed** on all distributions; the former global Makefile patch has been removed.

## SD boot and recovery
1. Connect 3.3 V TTL UART0, 115200 8N1, and capture the stock boot log.
2. Back up existing NAND/boot environment before experimentation; never run `nand erase`, `nand write`, `saveenv` or `flash_erase` without a tested recovery plan.
3. Confirm that stock U-Boot reads FAT partition 1 from `mmc 0:1`. The `uEnv.txt` file uses `bootz` and assumes root filesystem `/dev/mmcblk0p2`; these assumptions require hardware verification.
4. Write the image to a removable SD card **only after confirming the device path**. A mistaken `dd` destination destroys host data.
5. If boot fails, remove SD card and inspect the UART log. The scripts do not flash NAND.

## Security
This is an experimental development image. Do not expose Dropbear to untrusted networks until root authentication and SSH host keys have been provisioned. Do not rely on any documented historical `root/root` credentials. A root password/console policy must be explicitly configured and verified on hardware before network deployment.

## Engineering references
- [Porting guide](docs/porting_guide.md) — historical observations; some image details may be outdated.
- [Enhancement audit](docs/enhancement-audit.md) — remaining verification gates.
- [Hardware validation](docs/hardware-validation.md) — serial, boot, Ethernet and peripheral acceptance criteria.
