# Program-flash-kv260
Scripts to program a Kria platform via JTAG
# recovery
Assets and scripts to support Linux ssh based recovery mode for Kria
# lava
Lava integration notes, files and example jobs
# Google Docs
* [kv260 in board farm](https://docs.google.com/document/d/1WPiJrFQj5dPloldIa9zXi8KFF91dGdsFzdTM3DwKrDU/edit?usp=sharing)
# Notes
* SD card updating is slow but this is the speed of the target to that device
  * To reduce wear recovery does read/compare and write if needed for each 64M chuck
    + This should speed things up also in the normal case of writing an SD that
    is almost exactly the same as what is there already
    + Read speed for flash based devices should be faster than write speed
    + However, right now the read speed is not that fast
  * I was seeing ~10 S to read 64MB from SD card
    + I am using a PNY 16GB for testing
    + The Sandisk Ultra 32 GB cards may be faster
  * I was seeing ~3 S to read 64MB from USB stick
# Todo
* fix emmc for production SOM
  * hacking DTB in u-boot DID NOT fix this.  Needs investigation.
* Isolate boot failure: firmware, board, or test setup
* Better document OE build process for recorded assets (recovery-boot.bin cpio etc)
  * Some of this is now done
  * add OE builds to mk-recovery-assets.sh??
* lock down SSH to known keys only
* make meta-ts job deploy sdcard also
  * run 10 iterations of full meta-ts
* Add more LAVA example jobs
  * A firmware only job
* Move some of the device dictionary into a device type (?)
* figure out what is wrong with kpartx -d
* Do better disk image feedback in LAVA
  + LAVA logs appear line based.
  + Disk image feedback is 1 character per 64M chunk
  + This means no feedback for long periods
  + Add a mode or option to do line based feedback
## Maybe
* Handle file based overlays?  rsync deployment?
* add usb utils? sfdisk? mkfs.{ext4,vfat}
