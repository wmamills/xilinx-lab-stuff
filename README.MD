# Program-flash-kv260
Scripts to program a kira platform via JTAG
# recovery
Assets and scripts to support Linux ssh based recovery mode for Kira
# Google Docs
* [kv260 in board farm](https://docs.google.com/document/d/1WPiJrFQj5dPloldIa9zXi8KFF91dGdsFzdTM3DwKrDU/edit?usp=sharing)
# Todo
* fix emmc for production SOM
  * hacking DTB in u-boot DID NOT fix this.  Needs investigation.
* Better document OE build process for recorded assets (recovery-boot.bin cpio etc)
  * Some of this is now done
  * add OE builds to mk-recovery-assets.sh??
* lock down SSH to known keys only
* delete kira-recovey-update.sh support as it can not do recovery-boot.bin??
## Maybe
* add default for single *.wic[.gz] or *.iso[.xz] etc to go to SD?
* Handle file based overlays?  rsync deployment?
* add usb utils? sfdisk? mkfs.{ext4,vfat}
