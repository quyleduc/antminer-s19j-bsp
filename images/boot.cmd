echo Loading Buildroot Linux 6.6 from SD card...
setenv bootargs console=ttyO0,115200n8 earlycon=uart8250,mmio32,0x44e09000 root=/dev/mmcblk0p2 rw rootwait
fatload mmc 0:1 0x80008000 zImage || fatload mmc 0:1 0x80008000 uImage
fatload mmc 0:1 0x88000000 am335x.dtb || fatload mmc 0:1 0x88000000 am335x-antminer.dtb
bootz 0x80008000 - 0x88000000 || bootm 0x80008000 - 0x88000000
