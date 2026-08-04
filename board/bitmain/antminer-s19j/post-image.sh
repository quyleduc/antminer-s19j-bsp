#!/bin/sh
# Buildroot post-image script for Antminer S19J Control Board v2.5

BOARD_DIR="$(dirname $0)"
GENIMAGE_CFG="${BOARD_DIR}/genimage.cfg"
GENIMAGE_TMP="${BUILD_DIR}/genimage.tmp"

# Copy custom uEnv.txt to images directory
cp "${BOARD_DIR}/uEnv.txt" "${BINARIES_DIR}/uEnv.txt"

echo "Antminer S19J post-image generation completed."
