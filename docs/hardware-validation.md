# Hardware validation plan (S19J v2.5)

Record board revision, SoC marking, RAM/NAND markings, power rails and a serial log before each test. Never assume the BBB pinout.

| Gate | Method | Acceptance |
|---|---|---|
| NAND preservation | Read-only backup and hashes | Identical NAND before/after SD boot |
| SD boot | UART boot log with stock U-Boot | Kernel and DTB loaded from FAT partition 1 |
| Rootfs | /proc/cmdline, mount, dmesg | ext4 mounted from correct MMC partition |
| UART0 | Repeated single-character and burst input | No missing or delayed characters |
| Ethernet | ethtool, DHCP, ping, sustained transfer | Link and transfer stable, no PHY errors |
| SSH | Dropbear key authentication | Unique host keys, no default password |
| Memory | /proc/meminfo, stress testing | No OOM/kernel panic under expected load |
| DTS | dtc -I fs /proc/device-tree (where supported) | Correct enabled nodes and pinmux |
| GPIO/I2C/SPI | Trace physical nets, test one at a time | Only verified pads enabled |
| PRU | Review clocks, reset, power and sysc | Keep disabled until abort root cause verified |
| Recovery | Remove SD card, reboot | Factory NAND boot path still operational |

No hardware pass/fail results are included; this document defines acceptance criteria only.
