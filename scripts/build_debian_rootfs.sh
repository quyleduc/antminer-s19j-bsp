#!/bin/bash
# ==========================================================================
# Debian 12 (Bookworm) ARMhf RootFS Builder for Antminer S19J (TI AM335x)
# Requires: debootstrap, qemu-user-static, binfmt-support, e2fsprogs, python3
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
VFAT_IMG="${IMAGES_DIR}/boot.vfat"

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

# Step 1: Install prerequisite host packages & enable QEMU ARM binfmt
echo ">>> [1/7] Installing build host prerequisites..."
apt-get update -qq
apt-get install -y -qq debootstrap qemu-user-static binfmt-support e2fsprogs mtools parted openssl python3

echo ">>> Enabling QEMU ARM binfmt interpreter for chroot ARM execution..."
update-binfmts --enable qemu-arm 2>/dev/null || true
service binfmt-support start 2>/dev/null || true

# Step 2: Debootstrap Stage 1 & Stage 2
echo ">>> [2/7] Running debootstrap for Debian 12 Bookworm (armhf)..."
mkdir -p "${BUILD_DIR}"
rm -rf "${ROOTFS_DIR}"

debootstrap --foreign --arch=armhf bookworm "${ROOTFS_DIR}" http://deb.debian.org/debian/

# Copy QEMU static emulator for ARM target execution
cp /usr/bin/qemu-arm-static "${ROOTFS_DIR}/usr/bin/" 2>/dev/null || cp /usr/libexec/qemu-binfmt/arm-binfmt-P "${ROOTFS_DIR}/usr/bin/qemu-arm-static" 2>/dev/null || true

echo ">>> Completing Debian Stage 2 inside QEMU chroot..."
chroot "${ROOTFS_DIR}" /debootstrap/debootstrap --second-stage

# Step 3: Configure Target Debian System
echo ">>> [3/7] Configuring target system (packages, hostname, serial)..."

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
echo ">>> [4/7] Installing essential Debian packages & enabling SSH..."

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
    isc-dhcp-client \
    ifupdown \
    systemd-timesyncd \
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

# Enable systemd serial getty & NTP time sync
systemctl enable serial-getty@ttyS0.service
systemctl enable systemd-timesyncd.service

# Clean apt cache to reduce image size
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

# Step 6: Create dynamically-sized EXT4 RootFS Image
echo ">>> [5/7] Building EXT4 rootfs image..."
mkdir -p "${IMAGES_DIR}"
rm -f "${ROOTFS_IMG}"

# Calculate required size dynamically (actual size + 350MB free working space for user apt installs)
ACTUAL_SIZE_MB=$(du -sm "${ROOTFS_DIR}" | cut -f1)
REQUIRED_SIZE_MB=$((ACTUAL_SIZE_MB + 350))
echo "  Target RootFS content: ${ACTUAL_SIZE_MB} MB -> Creating ${REQUIRED_SIZE_MB} MB ext4 image..."

# Create dynamically-sized blank image file
dd if=/dev/zero of="${ROOTFS_IMG}" bs=1M count="${REQUIRED_SIZE_MB}"
mkfs.ext4 -F -L "rootfs" "${ROOTFS_IMG}"

# Copy files into ext4 image
MOUNT_TMP="${BUILD_DIR}/mnt"
mkdir -p "${MOUNT_TMP}"
mount -o loop "${ROOTFS_IMG}" "${MOUNT_TMP}"
cp -a "${ROOTFS_DIR}/"* "${MOUNT_TMP}/"
umount "${MOUNT_TMP}"

# Step 7: Build 64MB FAT32 boot partition (boot.vfat) with zImage, DTB, uEnv.txt
echo ">>> [6/7] Building 64MB FAT32 Boot Partition (boot.vfat)..."
rm -f "${VFAT_IMG}"
dd if=/dev/zero of="${VFAT_IMG}" bs=1M count=64
mkfs.fat -F 32 -n 'BOOT' "${VFAT_IMG}"
mmd -i "${VFAT_IMG}" ::/boot 2>/dev/null || true

# Copy uEnv.txt from board config if missing in images
if [ ! -f "${IMAGES_DIR}/uEnv.txt" ]; then
    cp "${PROJECT_DIR}/board/bitmain/antminer-s19j/uEnv.txt" "${IMAGES_DIR}/uEnv.txt"
fi

[ -f "${IMAGES_DIR}/zImage" ] && mcopy -o -i "${VFAT_IMG}" "${IMAGES_DIR}/zImage" ::/zImage
[ -f "${IMAGES_DIR}/uImage" ] && mcopy -o -i "${VFAT_IMG}" "${IMAGES_DIR}/uImage" ::/uImage
[ -f "${IMAGES_DIR}/uImage" ] && mcopy -o -i "${VFAT_IMG}" "${IMAGES_DIR}/uImage" ::/boot/uImage
[ -f "${IMAGES_DIR}/boot.scr" ] && mcopy -o -i "${VFAT_IMG}" "${IMAGES_DIR}/boot.scr" ::/boot.scr
[ -f "${IMAGES_DIR}/uEnv.txt" ] && mcopy -o -i "${VFAT_IMG}" "${IMAGES_DIR}/uEnv.txt" ::/uEnv.txt

if [ -f "${IMAGES_DIR}/am335x-antminer.dtb" ]; then
    mcopy -o -i "${VFAT_IMG}" "${IMAGES_DIR}/am335x-antminer.dtb" ::/am335x-boneblack.dtb
    mcopy -o -i "${VFAT_IMG}" "${IMAGES_DIR}/am335x-antminer.dtb" ::/boot/am335x-boneblack.dtb
    mcopy -o -i "${VFAT_IMG}" "${IMAGES_DIR}/am335x-antminer.dtb" ::/am335x.dtb
    mcopy -o -i "${VFAT_IMG}" "${IMAGES_DIR}/am335x-antminer.dtb" ::/antminer.dtb
fi

# Step 8: Update sdcard.img with Partition 1 (FAT32) & Partition 2 (EXT4)
echo ">>> [7/7] Bundling sdcard.img..."
python3 "${SCRIPT_DIR}/make_sdcard_img.py"

echo ""
echo "=========================================================="
echo " DEBIAN 12 (BOOKWORM) ROOTFS BUILD SUCCESSFUL!"
echo "=========================================================="
echo " RootFS Image: ${ROOTFS_IMG} (${REQUIRED_SIZE_MB} MB)"
echo " SD Card Image: ${IMAGES_DIR}/sdcard.img"
echo " Package:      apt / apt-get enabled"
echo " Serial:       ttyS0 (115200 8N1)"
echo " Network:      Auto-DHCP eth0"
echo " Access:       root / root (SSH & Serial)"
echo "=========================================================="
