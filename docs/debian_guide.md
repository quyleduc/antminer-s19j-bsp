# Antminer S19J Control Board v2.5 — Debian 12 (Bookworm) RootFS Guide

This guide explains how to build and run a full **Debian 12 (Bookworm) ARMhf** root filesystem on the Antminer S19J Control Board v2.5 (TI AM335x), enabling full **`apt` / `apt-get`** package management support.

---

## 1. Overview

While Buildroot provides an ultra-lightweight root filesystem (~50MB), Debian 12 provides a complete Linux distribution with full access to thousands of pre-compiled ARM packages via `apt-get install`.

| Feature | Buildroot 2025.02 | Debian 12 (Bookworm) |
|---------|-------------------|----------------------|
| **Kernel** | Linux 6.6.58 | Linux 6.6.58 |
| **Package Manager** | None (Pre-compiled) | `apt` / `apt-get` |
| **RootFS Size** | ~60 MB | ~100-300 MB |
| **SSH Server** | Dropbear | OpenSSH (`sshd`) |
| **Init System** | BusyBox Init | Systemd |
| **Best Used For** | Minimal production firmware | Software development / custom tools |

---

## 2. Building Debian 12 RootFS

To generate the Debian 12 armhf root filesystem image, run the automated build script on an Ubuntu / WSL host:

```bash
cd antminer-s19j-bsp
sudo ./scripts/build_debian_rootfs.sh
```

### Build Process Steps:
1. Installs host dependencies (`debootstrap`, `qemu-user-static`).
2. Bootstraps Debian 12 Bookworm `armhf` packages into a target chroot directory.
3. Installs essential utilities (`openssh-server`, `sudo`, `curl`, `wget`, `net-tools`, `i2c-tools`, `htop`, `git`).
4. Configures automatic DHCP networking on `eth0` and serial console on `ttyS0`.
5. Sets root password to `root` and enables root SSH login (`PermitRootLogin yes`).
6. Packages the output into `images/rootfs.ext4` and updates `images/sdcard.img`.

---

## 3. Access & Login Credentials

| Interface | Access Details |
|-----------|----------------|
| **Serial Console** | UART0 (115200 8N1), systemd getty on `ttyS0` |
| **SSH Server** | `ssh root@<BOARD_IP>` (Port 22, OpenSSH) |
| **Root Password** | `root` |
| **Package Manager** | `apt update && apt install <package>` |

---

## 4. Installing Packages on Board

Once booted into Debian 12 on the Antminer S19J board, you can use standard Debian package commands:

```bash
# Update package repositories
apt update

# Install software packages
apt install -y python3-pip git build-essential i2c-tools htop

# Install mining or hardware monitoring utilities
pip install --break-system-packages paho-mqtt requests
```

---

## 5. Switching Between Buildroot and Debian

- **To run Buildroot:** Run `./scripts/build.sh`
- **To run Debian 12:** Run `sudo ./scripts/build_debian_rootfs.sh`
