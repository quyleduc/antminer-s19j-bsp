#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION=2025.02
KERNEL_VERSION=6.6.58
BR="$ROOT/buildroot-$VERSION"
if [[ "$ROOT" == /mnt/[a-zA-Z]/* ]]; then
  echo "Build under WSL Linux filesystem, not /mnt/<drive>." >&2; exit 1
fi
for cmd in gcc make wget tar python3 rsync; do command -v "$cmd" >/dev/null || { echo "Missing $cmd" >&2; exit 1; }; done
"$ROOT/scripts/validate.sh"
if [[ ! -d "$BR" ]]; then
  archive="$ROOT/buildroot-$VERSION.tar.gz"
  wget -O "$archive.part" "https://buildroot.org/downloads/buildroot-$VERSION.tar.gz"
  mv "$archive.part" "$archive"
  tar -xzf "$archive" -C "$ROOT"
fi
# Preserve existing .config for iterative builds; explicit RESET_CONFIG=1 resets it.
if [[ ! -f "$BR/.config" || "${RESET_CONFIG:-0}" == 1 ]]; then
  make -C "$BR" BR2_DEFCONFIG="$ROOT/configs/antminer_s19j_defconfig" defconfig
fi
# Ensure Linux sources are extracted BEFORE injecting board-specific DTS.
make -C "$BR" linux-extract
DTS_DIR="$BR/output/build/linux-$KERNEL_VERSION/arch/arm/boot/dts/ti/omap"
test -d "$DTS_DIR" || { echo "Unexpected kernel DTS path: $DTS_DIR" >&2; exit 1; }
cp "$ROOT/board/bitmain/antminer-s19j/am335x-antminer.dts" "$DTS_DIR/"
MAKEFILE="$DTS_DIR/Makefile"
if ! grep -Eq '^[[:space:]]*dtb-.*am335x-antminer\.dtb' "$MAKEFILE"; then
  printf '\ndtb-$(CONFIG_SOC_AM33XX) += am335x-antminer.dtb\n' >> "$MAKEFILE"
fi
# Keep stock U-Boot/NAND untouched. Buildroot only builds Linux and rootfs.
make -C "$BR" -j"${JOBS:-$(nproc)}"
"$ROOT/scripts/package-image.sh"
echo "Image: $BR/output/images/sdcard.img"
