# Program-flash-kv260
Scripts to program a kira platform via JTAG
# recovery
Assets and scripts to support Linux ssh based recovery mode for Kira
# lava
Lava integration notes, files and example jobs
# Google Docs
* [kv260 in board farm](https://docs.google.com/document/d/1WPiJrFQj5dPloldIa9zXi8KFF91dGdsFzdTM3DwKrDU/edit?usp=sharing)
# Todo
* fix emmc for production SOM
  * hacking DTB in u-boot DID NOT fix this.  Needs investigation.
* Better document OE build process for recorded assets (recovery-boot.bin cpio etc)
  * Some of this is now done
  * add OE builds to mk-recovery-assets.sh??
* lock down SSH to known keys only
* Make it easier to deploy sdcard images
  * lava deploy can't rename or create symlinks and we want to download existing files
  * make kira-deploy take more arguments that specify symlinks to create
  * change device dict to pass along Image args
  * make meta-ts job deploy sdcard also
  * run 10 iterations of full meta-ts
* Add more LAVA example jobs
  * A firmware only job
  * A job with firmware and very small sdcard
* Move some of the device dictionary into a device type (?)
## Maybe
* Handle file based overlays?  rsync deployment?
* add usb utils? sfdisk? mkfs.{ext4,vfat}
