
setenv netload  "tftpboot 0xE00000 5050a/Image ; tftpboot 0x20A00000 5050a/system-brian.dtb; tftpboot 0x4000000 5050a/versal-virtio-msg-demo-image-versal-generic.rootfs.cpio.gz.u-boot"
setenv bootargs "console=ttyAMA0  earlycon=pl011,mmio32,0xFF000000,115200n8 clk_ignore_unused root=/dev/mmcblk1p2 rw uio_pdrv_genirq.of_id=generic-uio rootwait cma=768M"
setenv netboot  "dhcp; run netload; booti 0xE00000 0x4000000 0x20A00000"


# DTB preloaded over JTAG
setenv mmcload "mmc dev 1 1 ; load mmc 1:1 0xE00000 /Image"
setenv mmcboot "run mmcload; booti 0xE00000 - 0x20A00000"
setenv mmcboot-xen "mmc dev 1 1 ; load mmc 1:1 0xE00000 /xen.efi; bootefi 0xE00000 0x20A00000"

echo Available commands
echo netboot
echo mmcboot
echo mmcboot-xen

