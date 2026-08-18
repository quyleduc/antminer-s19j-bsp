#!/bin/bash
# ==========================================================================
# One-click Build Script for Antminer S19J Control Board v2.5 Buildroot BSP
# Compatible with: Ubuntu 22.04 LTS (GCC 11) / 24.04 (GCC 14) / 26.04 (GCC 15)
# ==========================================================================

set -e

# Sanitize PATH for WSL & CI (Removes Windows paths containing spaces/tabs)
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

BUILDROOT_VERSION="2025.02"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILDROOT_DIR="${PROJECT_DIR}/buildroot-${BUILDROOT_VERSION}"
IMAGES_DIR="${PROJECT_DIR}/images"

# --------------------------------------------------------------------------
# Helper Functions
# --------------------------------------------------------------------------

log_step() {
    echo ""
    echo ">>> [$1] $2"
    echo "------------------------------------------------------------"
}

check_dependencies() {
    local missing=()
    for cmd in make gcc g++ wget tar bc cpio rsync sed python3 mtools mkfs.fat; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    # Check for OpenSSL headers (required for Linux kernel certs/extract-cert)
    if [ ! -f "/usr/include/openssl/bio.h" ]; then
        missing+=("libssl-dev")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        echo "ERROR: Missing required tools or headers: ${missing[*]}"
        echo "Install them with:"
        echo "  sudo apt update && sudo apt install -y build-essential libssl-dev wget git bc cpio rsync unzip libncurses-dev python3 mtools dosfstools"
        exit 1
    fi
}

get_gcc_major_version() {
    gcc -dumpversion 2>/dev/null | cut -d. -f1
}

# --------------------------------------------------------------------------
# Pre-flight Checks
# --------------------------------------------------------------------------

# Check NTFS mount (WSL building on Windows drive)
if [[ "$PROJECT_DIR" == /mnt/[a-zA-Z]/* ]]; then
    echo "=========================================================="
    echo " ERROR: Cannot build on Windows NTFS drive ($PROJECT_DIR)"
    echo " NTFS does not support Linux POSIX permissions & symlinks."
    echo ""
    echo " Fix: Copy project to your Linux home directory:"
    echo "   cp -r $PROJECT_DIR ~/antminer-s19j-bsp"
    echo "   cd ~/antminer-s19j-bsp && ./scripts/build.sh"
    echo "=========================================================="
    exit 1
fi

check_dependencies

GCC_VER=$(get_gcc_major_version)
UBUNTU_VER=$(lsb_release -rs 2>/dev/null || echo "unknown")

echo "=========================================================="
echo " Antminer S19J v2.5 - Buildroot BSP Builder"
echo "=========================================================="
echo " Ubuntu:     ${UBUNTU_VER}"
echo " GCC:        ${GCC_VER}"
echo " Buildroot:  ${BUILDROOT_VERSION}"
echo " Project:    ${PROJECT_DIR}"
echo "=========================================================="

# --------------------------------------------------------------------------
# Step 1: Download & Extract Buildroot
# --------------------------------------------------------------------------

if [ ! -d "${BUILDROOT_DIR}" ]; then
    log_step "1/6" "Downloading Buildroot ${BUILDROOT_VERSION}..."
    wget -c "https://buildroot.org/downloads/buildroot-${BUILDROOT_VERSION}.tar.gz" \
         -O "${PROJECT_DIR}/buildroot.tar.gz"

    log_step "1/6" "Extracting Buildroot..."
    tar -xzf "${PROJECT_DIR}/buildroot.tar.gz" -C "${PROJECT_DIR}" --no-same-owner \
        || tar -xzf "${PROJECT_DIR}/buildroot.tar.gz" -C "${PROJECT_DIR}"
    rm -f "${PROJECT_DIR}/buildroot.tar.gz"
else
    log_step "1/6" "Buildroot already extracted, skipping download."
fi

cd "${BUILDROOT_DIR}"

# --------------------------------------------------------------------------
# Step 2: Apply GCC version-specific patches (GLOBAL fix for ALL host pkgs)
# --------------------------------------------------------------------------

log_step "2/6" "Checking host GCC compatibility..."

if [ -n "${GCC_VER}" ] && [ "${GCC_VER}" -ge 14 ] 2>/dev/null; then
    echo "  GCC ${GCC_VER} detected (C23 default) -> Applying GLOBAL host CFLAGS patch"

    MAKEFILE_IN="${BUILDROOT_DIR}/package/Makefile.in"
    if [ -f "${MAKEFILE_IN}" ]; then
        if ! grep -q "std=gnu17" "${MAKEFILE_IN}"; then
            sed -i 's/^HOST_CFLAGS\s*=\s*-O2/HOST_CFLAGS = -O2 -std=gnu17/' "${MAKEFILE_IN}"
            echo "  -> Patched ${MAKEFILE_IN}: HOST_CFLAGS += -std=gnu17"
        else
            echo "  -> ${MAKEFILE_IN} already patched, skipping."
        fi
    fi

    # Clean any previously failed host package builds
    for pkg in host-m4-1.4.19 host-gmp-6.3.0; do
        if [ -d "${BUILDROOT_DIR}/output/build/${pkg}" ]; then
            echo "  -> Cleaning stale ${pkg} build..."
            rm -rf "${BUILDROOT_DIR}/output/build/${pkg}"
        fi
    done
else
    echo "  GCC ${GCC_VER:-unknown} detected (C17 default) -> No patches needed"
fi

# --------------------------------------------------------------------------
# Step 3: Apply Buildroot defconfig
# --------------------------------------------------------------------------

log_step "3/6" "Applying Antminer S19J defconfig..."
mkdir -p "${BUILDROOT_DIR}/configs"
cp "${PROJECT_DIR}/configs/antminer_s19j_defconfig" "${BUILDROOT_DIR}/configs/antminer_s19j_defconfig"
make -C "${BUILDROOT_DIR}" antminer_s19j_defconfig

# --------------------------------------------------------------------------
# Step 4: Copy board-specific files & Linux 6.6 DTSI layout
# --------------------------------------------------------------------------

log_step "4/6" "Copying custom Device Tree & board files..."
mkdir -p "${BUILDROOT_DIR}/board/bitmain/antminer-s19j"
cp -r "${PROJECT_DIR}/board/bitmain/antminer-s19j/"* "${BUILDROOT_DIR}/board/bitmain/antminer-s19j/"

# Trigger linux-extract so kernel source tree is prepared on clean builds
echo "  Extracting Linux Kernel sources..."
make -C "${BUILDROOT_DIR}" linux-extract

# Linux 6.6 stores TI AM335x DTS files under arch/arm/boot/dts/ti/omap/
KERNEL_DTS_DIR="${BUILDROOT_DIR}/output/build/linux-6.6.58/arch/arm/boot/dts"
mkdir -p "${KERNEL_DTS_DIR}/ti/omap"
cp "${PROJECT_DIR}/board/bitmain/antminer-s19j/am335x-antminer.dts" "${KERNEL_DTS_DIR}/ti/omap/am335x-antminer.dts"
echo "  -> Installed custom am335x-antminer.dts into kernel arch/arm/boot/dts/ti/omap/"

# --------------------------------------------------------------------------
# Step 5: Build with Buildroot
# --------------------------------------------------------------------------

NPROC=$(nproc 2>/dev/null || echo 1)
log_step "5/6" "Building Buildroot target with ${NPROC} parallel jobs..."
make -C "${BUILDROOT_DIR}" -j${NPROC}

# --------------------------------------------------------------------------
# Step 6: Package Artifacts into images/ and bundle sdcard.img
# --------------------------------------------------------------------------

log_step "6/6" "Packaging Bootloader, Kernel, DTB, RootFS into sdcard.img..."
mkdir -p "${IMAGES_DIR}"

# Copy outputs from Buildroot
cp "${BUILDROOT_DIR}/output/images/zImage" "${IMAGES_DIR}/zImage" 2>/dev/null || true

if [ -f "${BUILDROOT_DIR}/output/images/am335x-antminer.dtb" ]; then
    cp "${BUILDROOT_DIR}/output/images/am335x-antminer.dtb" "${IMAGES_DIR}/am335x-antminer.dtb"
elif [ -f "${BUILDROOT_DIR}/output/images/ti/omap/am335x-antminer.dtb" ]; then
    cp "${BUILDROOT_DIR}/output/images/ti/omap/am335x-antminer.dtb" "${IMAGES_DIR}/am335x-antminer.dtb"
fi

cp "${BUILDROOT_DIR}/output/images/rootfs.ext4" "${IMAGES_DIR}/rootfs.ext4" 2>/dev/null || \
   cp "${BUILDROOT_DIR}/output/images/rootfs.ext2" "${IMAGES_DIR}/rootfs.ext4" 2>/dev/null || true

# Build 64MB FAT32 boot partition (boot.vfat)
VFAT_IMG="${IMAGES_DIR}/boot.vfat"
rm -f "${VFAT_IMG}"
dd if=/dev/zero of="${VFAT_IMG}" bs=1M count=64 status=none
mkfs.fat -F 32 -n 'BOOT' "${VFAT_IMG}" >/dev/null
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

# Bundle sdcard.img
python3 "${PROJECT_DIR}/scripts/make_sdcard_img.py"

# --------------------------------------------------------------------------
# Done
# --------------------------------------------------------------------------

echo ""
echo "=========================================================="
echo " BUILD SUCCESSFUL!"
echo "=========================================================="
echo " Ubuntu ${UBUNTU_VER} / GCC ${GCC_VER}"
echo ""
echo " Output Artifacts: ${IMAGES_DIR}/"
echo "   - sdcard.img            (Complete Flashable Disk Image)"
echo "   - zImage                (Linux 6.6.58 Kernel)"
echo "   - am335x-antminer.dtb  (Custom Device Tree Blob)"
echo "   - rootfs.ext4           (Root Filesystem)"
echo "   - boot.vfat             (FAT32 Boot Partition)"
echo ""
echo " Flash to SD card with BalenaEtcher, Rufus, or dd:"
echo "   sudo dd if=${IMAGES_DIR}/sdcard.img of=/dev/sdX bs=4M status=progress conv=fsync"
echo "=========================================================="
