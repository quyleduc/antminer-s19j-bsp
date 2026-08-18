# Antminer S19J Control Board v2.5 (AM335x) — Buildroot BSP & Debian 12 Linux 6.6 Port

Full Board Support Package (BSP), Debian 12 (Bookworm) RootFS, and automated CI/CD pipeline for running modern **Linux Kernel 6.6.58** on the **Antminer S19J Control Board v2.5** (TI AM335x) via SD Card — leaving the original NAND Flash, SPL, and stock U-Boot 2013.04 untouched and completely safe.

---

## 📁 Repository Structure

```text
antminer-s19j-bsp/
├── README.md                           # Main Documentation
├── .gitignore                          # Git ignore rules for build artifacts
├── .github/
│   └── workflows/
│       └── build-images.yml            # Automated CI/CD GitHub Actions Workflow
├── board/
│   └── bitmain/
│       └── antminer-s19j/
│           ├── am335x-antminer.dts     # Custom Device Tree (PRUSS/LCDC disabled, UART0 PIO)
│           ├── uEnv.txt                # U-Boot Auto-boot file for SD Card
│           └── boot.cmd                # U-Boot boot script source
├── configs/
│   └── antminer_s19j_defconfig        # Buildroot Defconfig (Linux 6.6 + Dropbear SSH)
├── docs/
│   ├── porting_guide.md                # Comprehensive BSP Porting Guide & Hardware Quirks
│   ├── debian_guide.md                 # Debian 12 Bookworm RootFS & apt Guide
│   └── ci_cd_guide.md                  # GitHub Actions CI/CD & Release Automation Guide
└── scripts/
    ├── build.sh                        # Buildroot 2025.02 image builder & packager
    ├── build_debian_rootfs.sh          # Debian 12 (Bookworm) armhf image builder
    └── make_sdcard_img.py              # Automated MBR SD Card disk image builder
```

---

## 🚀 Quick Start (Building on Ubuntu / WSL)

### Option A: Build Buildroot Image (~60MB RootFS)
```bash
git clone <repo_url> antminer-s19j-bsp
cd antminer-s19j-bsp
chmod +x scripts/*.sh
./scripts/build.sh
```

### Option B: Build Debian 12 Bookworm Image (with `apt` / `apt-get`)
```bash
sudo ./scripts/build_debian_rootfs.sh
```

### Flashing to SD Card (`sdcard.img`)
```bash
# Flash images/sdcard.img directly to your SD card device (e.g. /dev/sdX or BalenaEtcher)
sudo dd if=images/sdcard.img of=/dev/sdX bs=4M status=progress conv=fsync
```

---

## 🤖 CI/CD & Automated GitHub Releases

This repository includes a full GitHub Actions workflow (`.github/workflows/build-images.yml`):
- **Quality Gates:** ShellCheck linting, Python validation, and BSP sanity checks on every PR / Push.
- **Automated Builds:** Builds both **Buildroot** and **Debian 12** disk images in parallel with Buildroot download caching.
- **Automated Release Deployment:** Tagging a release (`git tag v1.0.0 && git push origin v1.0.0`) automatically publishes high-compression `.img.xz` disk images and SHA256 checksums to GitHub Releases.

For details, read [`docs/ci_cd_guide.md`](docs/ci_cd_guide.md).

---

## 🔑 Login & Access Credentials

| Service | Access Details |
|---------|----------------|
| **Serial Console** | UART0 (115200 8N1), direct root shell on `ttyS0` |
| **SSH Server** | `ssh root@<BOARD_IP>` (Port 22, Dropbear / OpenSSH) |
| **Root Password** | `root` |
| **Network** | Automatic DHCP on `eth0` |

---

## 🔑 Key Engineering Discoveries & Solutions

1. **PRU-ICSS External Abort Panic (0x4a326000):**
   - Disabling `&pruss` **and** interconnect target module `&pruss_tm` in `am335x-antminer.dts` prevents `ti-sysc` from probing unclocked PRU hardware.

2. **UART0 DMA vs Terminal Unresponsiveness:**
   - Removing `dmas` and `dma-names` from `&uart0` in DTS forces PIO mode (interrupt-driven), immediately delivering single keypresses from PuTTY / terminal without trapping data in eDMA buffers.

3. **Serial Naming (Linux 6.6):**
   - AM335x UART0 is exposed as `/dev/ttyS0` (8250_omap driver). A runtime device node `/dev/ttyO0` is created for backward compatibility.

4. **Time Sync & APT Validation:**
   - Pre-configured `systemd-timesyncd` for automatic network time synchronization on boot, preventing APT repository release expiration errors.

---

## 📜 Documentation Index

- [`docs/porting_guide.md`](docs/porting_guide.md): Technical deep dive into AM335x hardware quirks, kernel crashes, and fixes.
- [`docs/debian_guide.md`](docs/debian_guide.md): Guide to Debian 12 Bookworm armhf rootfs with `apt` package management.
- [`docs/ci_cd_guide.md`](docs/ci_cd_guide.md): GitHub Actions CI/CD pipelines, caching, and automated releases.

---

## 📜 License
MIT License / GPLv2.
