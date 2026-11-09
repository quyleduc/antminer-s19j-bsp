#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BR="$ROOT/buildroot-2025.02"
IMAGES="$BR/output/images"
STAGING="$BR/output/antminer-boot"
for file in zImage am335x-antminer.dtb rootfs.ext4; do
  test -s "$IMAGES/$file" || { echo "Missing image artifact: $file" >&2; exit 1; }
done
GENIMAGE="$BR/output/host/bin/genimage"
test -x "$GENIMAGE" || { echo "Missing host genimage (enable BR2_PACKAGE_HOST_GENIMAGE)" >&2; exit 1; }
mkdir -p "$STAGING"
cp "$IMAGES/zImage" "$IMAGES/am335x-antminer.dtb" "$STAGING/"
cp "$IMAGES/am335x-antminer.dtb" "$STAGING/am335x-boneblack.dtb"
cp "$ROOT/board/bitmain/antminer-s19j/uEnv.txt" "$STAGING/"
# Both FAT root and /boot alias are supported by documented stock U-Boot.
mkdir -p "$STAGING/boot"
cp "$IMAGES/am335x-antminer.dtb" "$STAGING/boot/am335x-boneblack.dtb"
rm -rf "$BR/output/genimage.tmp"
"$GENIMAGE" --rootpath "$STAGING" --tmppath "$BR/output/genimage.tmp" --inputpath "$STAGING" --outputpath "$IMAGES" --config "$ROOT/board/bitmain/antminer-s19j/genimage.cfg"
test -s "$IMAGES/sdcard.img"
