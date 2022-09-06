# Program-flash-kv260
Scripts to program a kira platform via JTAG
# recovery
Assets and scripts to support Linux ssh based recovery mode for Kira
# Google Docs
* [kv260 in board farm](https://docs.google.com/document/d/1WPiJrFQj5dPloldIa9zXi8KFF91dGdsFzdTM3DwKrDU/edit?usp=sharing)
# Todo
* get real eth mac addr to recovery Linux so it stops getting a new IP each time
* fix emmc and USB for production SOM
  * fix DTB matching in u-boot will probably do it
* Better document OE build process for recorded assets (recovery-boot.bin cpio etc)
* lock down SSH to known keys only
* tweak host name to kira-recovery
* handle recovery asset update via sd image w/ u-boot script
  * delete kira-recovey-update.sh support as it can not do recovery-boot.bin
## Maybe
* add default for single *.wic[.gz] or *.iso[.xz] etc to go to SD?
* Handle file based overlays?  rsync deployment?
* add usb utils? sfdisk? mkfs.{ext4,vfat}
