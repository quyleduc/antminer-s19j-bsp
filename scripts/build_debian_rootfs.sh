#!/bin/bash
# ==========================================================================
# Debian 12 (Bookworm) ARMhf RootFS Builder for Antminer S19J (TI AM335x)
# Requires: debootstrap, qemu-user-static, e2fsprogs
# ==========================================================================

set -e

# Sanitize PATH for WSL
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build_debian"
IMAGES_DIR="${PROJECT_DIR}/images"
ROOTFS_DIR="${BUILD_DIR}/rootfs"
ROOTFS_IMG="${IMAGES_DIR}/rootfs.ext4"

# Check root privilege for debootstrap/mount
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root (sudo ./scripts/build_debian_rootfs.sh)"
    exit 1
fi

echo "=========================================================="
echo " Antminer S19J - Debian 12 (Bookworm) RootFS Builder"
echo "=========================================================="
echo " Architecture: armhf (ARMv7-A Cortex-A8)"
echo " Target OS:    Debian 12 Bookworm"
echo " Output:       ${ROOTFS_IMG}"
echo "=========================================================="

# Step 1: Install prerequisite host packages
echo ">>> [1/6] Installing build host prerequisites..."
apt-get update -qq
apt-get install -y -qq debootstrap qemu-user-static e2fsprogs mtools parted openssl

# Step 2: Debootstrap Stage 1 & Stage 2
echo ">>> [2/6] Running debootstrap for Debian 12 Bookworm (armhf)..."
mkdir -p "${BUILD_DIR}"
rm -rf "${ROOTFS_DIR}"

debootstrap --foreign --arch=armhf bookworm "${ROOTFS_DIR}" http://deb.debian.org/debian/

# Copy QEMU static emulator for ARM target execution
cp /usr/bin/qemu-arm-static "${ROOTFS_DIR}/usr/bin/"

echo ">>> Completing Debian Stage 2 inside QEMU chroot..."
chroot "${ROOTFS_DIR}" /debootstrap/debootstrap --second-stage

# Step 3: Configure Target Debian System
echo ">>> [3/6] Configuring target system (packages, hostname, serial)..."

# Set Hostname
echo "antminer-s19j" > "${ROOTFS_DIR}/etc/hostname"

# Configure FSTAB
cat > "${ROOTFS_DIR}/etc/fstab" << 'EOF'
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
/dev/mmcblk0p2  /               ext4    errors=remount-ro,noatime 0 1
proc            /proc           proc    defaults        0       0
devpts          /dev/pts        devpts  gid=5,mode=620  0       0
tmpfs           /tmp            tmpfs   defaults        0       0
EOF

# Configure Network Interfaces (DHCP on eth0)
cat > "${ROOTFS_DIR}/etc/network/interfaces" << 'EOF'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF

# Step 4: Run chroot configuration for packages & root password
echo ">>> [4/6] Installing essential Debian packages & enabling SSH..."

cat > "${ROOTFS_DIR}/tmp/setup.sh" << 'EOF'
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive

# Update apt sources
cat > /etc/apt/sources.list << 'SOURCES'
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb http://deb.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
SOURCES

apt-get update -qq
apt-get install -y -qq \
    openssh-server \
    sudo \
    curl \
    wget \
    net-tools \
    iproute2 \
    ethtool \
    i2c-tools \
    lm-sensors \
    nano \
    htop \
    git \
    systemd-sysv

# Set root password to "root"
echo "root:root" | chpasswd

# Configure SSH for root login
sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config

# Enable systemd serial getty on ttyS0
systemctl enable serial-getty@ttyS0.service

# Clean apt cache
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/*
EOF

chmod +x "${ROOTFS_DIR}/tmp/setup.sh"
chroot "${ROOTFS_DIR}" /tmp/setup.sh

# Remove QEMU binary from target
rm -f "${ROOTFS_DIR}/usr/bin/qemu-arm-static"

# Step 5: Add /dev/ttyO0 compatibility script
cat > "${ROOTFS_DIR}/etc/rc.local" << 'EOF'
#!/bin/sh
mknod /dev/ttyO0 c 4 64 2>/dev/null || ln -sf /dev/ttyS0 /dev/ttyO0
exit 0
EOF
chmod +x "${ROOTFS_DIR}/etc/rc.local"

# Step 6: Create 100MB EXT4 RootFS Image
echo ">>> [5/6] Building EXT4 rootfs image..."
mkdir -p "${IMAGES_DIR}"
rm -f "${ROOTFS_IMG}"

# Create 100MB blank image file
dd if=/dev/zero of="${ROOTFS_IMG}" bs=1M count=100
mkfs.ext4 -F -L "rootfs" "${ROOTFS_IMG}"

# Copy files into ext4 image
MOUNT_TMP="${BUILD_DIR}/mnt"
mkdir -p "${MOUNT_TMP}"
mount -o loop "${ROOTFS_IMG}" "${MOUNT_TMP}"
cp -a "${ROOTFS_DIR}/"* "${MOUNT_TMP}/"
umount "${MOUNT_TMP}"

# Step 7: Update sdcard.img with new Debian RootFS
echo ">>> [6/6] Updating sdcard.img Partition 2 with Debian 12 RootFS..."
if [ -f "${IMAGES_DIR}/sdcard.img" ]; then
    dd if="${ROOTFS_IMG}" of="${IMAGES_DIR}/sdcard.img" bs=1M seek=33 conv=notrunc
fi

echo ""
echo "=========================================================="
echo " DEBIAN 12 (BOOKWORM) ROOTFS BUILD SUCCESSFUL!"
echo "=========================================================="
echo " Image:    ${ROOTFS_IMG}"
echo " Package:  apt / apt-get enabled"
echo " Serial:   ttyS0 (115200 8N1)"
echo " Network:  Auto-DHCP eth0"
echo " Access:   root / root (SSH & Serial)"
echo "=========================================================="
