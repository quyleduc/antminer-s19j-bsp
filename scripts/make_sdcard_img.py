#!/usr/bin/env python3
"""
Python script to bundle FAT32 boot + EXT4 rootfs into a single sdcard.img
for BalenaEtcher / Rufus / Win32DiskImager on Windows.
Uses absolute path resolution derived from script location.
"""

import os
import struct
import shutil

def create_mbr(fat_start_sec, fat_size_sec, ext_start_sec, ext_size_sec):
    mbr = bytearray(512)
    # Magic bytes
    mbr[510] = 0x55
    mbr[511] = 0xAA

    # Partition 1: FAT32 (Bootable)
    struct.pack_into(
        "<B3sB3sII", mbr, 446,
        0x80,                      # Bootable
        b"\x00\x00\x00",           # CHS Start
        0x0C,                      # FAT32 LBA
        b"\x00\x00\x00",           # CHS End
        fat_start_sec,             # Start LBA
        fat_size_sec               # Size in Sectors
    )

    # Partition 2: Linux EXT4
    struct.pack_into(
        "<B3sB3sII", mbr, 462,
        0x00,                      # Non-bootable
        b"\x00\x00\x00",           # CHS Start
        0x83,                      # Linux
        b"\x00\x00\x00",           # CHS End
        ext_start_sec,             # Start LBA
        ext_size_sec               # Size in Sectors
    )

    return mbr

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_dir = os.path.abspath(os.path.join(script_dir, ".."))
    images_dir = os.path.abspath(os.path.join(project_dir, "images"))

    ext4_path = os.path.abspath(os.path.join(images_dir, "rootfs.ext4"))
    sdcard_path = os.path.abspath(os.path.join(images_dir, "sdcard.img"))

    if not os.path.exists(ext4_path):
        print(f"Error: {ext4_path} not found.")
        return

    ext4_size = os.path.getsize(ext4_path)
    ext4_sectors = (ext4_size + 511) // 512

    fat_start_sec = 2048           # 1MB offset
    fat_size_sec = 65536           # 32MB FAT32 partition
    ext_start_sec = fat_start_sec + fat_size_sec # Sector 67584
    ext_size_sec = ext4_sectors

    total_sectors = ext_start_sec + ext_size_sec
    total_bytes = total_sectors * 512

    print(f"Creating MBR disk image: {sdcard_path}")
    print(f"  Total size: {total_bytes / (1024*1024):.2f} MB")
    print(f"  FAT32 Boot: Sector {fat_start_sec} ({fat_size_sec * 512 / (1024*1024):.1f} MB)")
    print(f"  EXT4 RootFS: Sector {ext_start_sec} ({ext_size_sec * 512 / (1024*1024):.1f} MB)")

    # 1. Create empty file with MBR
    with open(sdcard_path, "wb") as f:
        mbr = create_mbr(fat_start_sec, fat_size_sec, ext_start_sec, ext_size_sec)
        f.write(mbr)
        # Pad to FAT32 start
        f.seek(fat_start_sec * 512 - 1)
        f.write(b"\x00")

        # Write EXT4 rootfs directly at sector ext_start_sec
        f.seek(ext_start_sec * 512)
        with open(ext4_path, "rb") as ext_f:
            shutil.copyfileobj(ext_f, f)

    print(f"SUCCESS: {sdcard_path} generated!")

if __name__ == "__main__":
    main()
