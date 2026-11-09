#!/usr/bin/env bash
# Static checks; no board access or cross toolchain required.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
python3 - <<'PY'
from pathlib import Path
cfg=Path("configs/antminer_s19j_defconfig").read_text()
env=Path("board/bitmain/antminer-s19j/uEnv.txt").read_text()
dts=Path("board/bitmain/antminer-s19j/am335x-antminer.dts").read_text()
assert 'BR2_LINUX_KERNEL_INTREE_DTS_NAME="ti/omap/am335x-antminer"' in cfg
assert 'bootfile=zImage' in env and 'fdtfile=am335x-antminer.dtb' in env
assert 'bootz ${loadaddr} - ${fdtaddr}' in env
assert '&pruss_tm' in dts and 'status = "disabled"' in dts
assert 'root=/dev/mmcblk0p2' in env
print("PASS: BSP static boot/configuration consistency checks")
PY
