# Notes on QSPI locking for kv260 Production SOM

There is a SD card image that can be booted on a kv260 production SOM that will
boot, lock the first 1M of QSPI, and then power-down.  The lock-qspi script will
run automatically at startup but gives you a 5 second delay before running in case
you want to run manually or do something else.  Likewise, there is a stoppable
5 second delay after running before the powerdown is executed.

This image is here:
https://people.linaro.org/~bill.mills/xilinx-lab-stuff/kv260-prodsom-lock-qspi.img.bz2

Use with this boot.bin:
https://people.linaro.org/~bill.mills/xilinx-images/rebuilt-2023.2-kv260/boot.bin

(In theory any boot.bin that boots from sd card by default and handles boot.scr
*should* work but testing has shown problems.  Trusted Substrate builds won't
process boot.scr by default.  AMD 2025.1 wont boot. AMD 2024.2 has a u-boot menu
and boots from emmc by default and won't see the emmc if sd is manually selected.
AMD 2024.1 won't see the emmc so the script fails. etc )

## An aside on the Starter SOM

Note: The Stater SOM already has (*most?*) recovery assets already lock using 
a more secure method.  This method can use non-volatile locking of any number of
randomly placed 64K blocks in the QSPI.  It is also password protected and AMD
does not share the password so a test job *should* never be able to brick
recovery mode.

### Doubts on Starter SOM lock robustness

The words "most" and *should* in the prior section are due to one doubt.
The "Persistent_Register" area in mtd2 and its backup copy in mtd3 specify
if Image A or Image B are bootable and which is preferred.
As this changes during firmware updates, these partitions / blocks need to be
read/write.

However, I believe the register also contains the offsets in the QSPI of 
Image A, Image B and the Recovery Image.
So if one were to erase both mtd2 and mtd3, would recovery sill work or would it
fail? 

Perhaps the ImgSel has default offsets built-in and it would not fail.
If it does fail the board *should* be recoverable with JTAG.

I have never been brave enough to test this.

## Goal: prevent poorly behaved test jobs from bricking the board so that recovery won't run

There is a some recent (2025 July & August) test job that has broken the boards
so that recovery won't run.  It has taken out multiple boards in the lab.
Reprogramming via JTAG fixes the boards but this is not easy as the JTAG tools
will not run on the arm64 processor on the LAA.
In fact no arm64 version of the JTAG tools are know to exist.  This means the
boards have to be removed from the LAA, taken to an x86 PC and reprogrammed.

## Method: Use SR locking to lock the bottom 1M of QSPI

Ideally we would use the same locking method on the production SOM that AMD does
on the starter SOM.  However no implementation of this in u-boot or Linux kernel
is known to exist.  AMD uses a bare-metal program to do this and currently can't
share this as it is propriety to their board production and has AMD secrets
(like the password) in them.  AMD may look at producing a version for Production
SOM users but this will take time.

The [AMD "Xilinx" v6.12 kernel](https://github.com/Xilinx/linux-xlnx/tree/xlnx_rebase_v6.12_LTS_2025.1_update) has support for locking QSPI using the Status
Register (SR) method.  This method in general supports locking N 64K blocks
starting from the bottom (0 offset) or from the top (max offset).
The Xilinx kernel has only been tested with bottom locking but that is what we
need.

The upstream kernel has some locking support for the QSPI on the K26 SOM,
a Micron MT25QU512ABB8E12, but the Xilinx kernel has changes that look important
and has been tested on the parts used by AMD.  So we will use the Xilinx kernel.

## Limitations of SR based locking

* Can only protect a continuos range of blocks at the start of flash
  * HW supports a range at the end of flash as a mutually exclusive option.
  This support is not tested/supported in the AMD Xilinx kernel
  * We cannot protect mtd0, mtd1, mtd10, mtd14, and mtd15 and leave all others unlocked
* The SR locking method is well known and not protected by a password
  * Anyone can unlock it
  * Some software routinely unlocks blocks it plans to update or the whole flash before updating
  * We cannot protect ourselves from this; this is a best-effort method

## How the SD card is created

* Start with a copy of a minimal boot image from AMD 2025.1 release
  * This can be built via [this script](https://github.com/wmamills-org/openamp-ci-builds/blob/wip-2025-04/for-ref/xilinx-vendor.sh)
  * A copy of the built image can be found [here](https://people.linaro.org/~bill.mills/xilinx-images/rebuilt-2025.1-kv260/petalinux-image-minimal-k26-smk-kv.wic.xz)
  * Note the stock dtb in this image uses the wrong serial port in chosen stdout-path so no kernel logs are present at boot time.  A serial login console *is* still created at the correct serial port
* Add the files this repo and dir
  * run make in the boot/ dir
  * copy all file in boot/ to the first partition of the sd card from above
  * copy all files from rootfs/ to the second partition of the sd card
  * make sure all copied files are chown root:root on the sd card
* Test the sd card
* Save the sd card image

```
sudo dd if=/dev/sdd of=kv260-prodsom-lock-qspi.img bs=1M count=1024
bzip2 -k kv260-prodsom-lock-qspi.img
```

## Details

The autologin and autorun support was reused from other projects.

The passwd and shadow files were created by logging into the stock image and
doing the following commands:

```
sudo passwd -d root
sudo passwd -d petalinux
```

The kernel and initramfs files are used as-is from the AMD image above.

The boot.scr is cut down to do only what is needed.  It uses the custom dtb
described below and adds command line arguments for autorun.

### Details for the DTB

All the magic is in the DTB.

* Started with a dtb from a kernel.org v6.12 build for kv260 w/ production SOM
* Created dts from that
* Made these changes under /axi/spi@ff0f0000/flash@0
  * added property no-wp
  * for all partitions that had them, delete the read-only and lock properties
  * deleted the second partition and doubled the size of the first one

We use a production SOM DTB so we have a /dev/mmcblk0* device nodes to use to
verify that we really are on a production SOM.

By default the kernel will set the "Status Register Write Disable" bit
(SRWD, bit7) in the status register (SR) when performing a lock operation.
This prevents and further changes to the SR while the W# pin is asserted.
As we do not have reliable/easy control of the W# signal on the Kria SOM,
this may cause issues.
The no-wp property at the base of the QSPI DT disables this behavior so that
locking does not set the SRWP bit in the SR.

The flash_lock operation failed on mtd0 when it had the read-only property.
Likewise, I believe the operation was not really working if the lock property 
was present.  I removed both of these properties from all partitions to make
sure.

With the original partition layout, I was not able to lock 16 blocks (1M) using
/dev/mtd0; I could only lock 8 blocks (512K), the size of mtd0.
I tried locking 8 blocks in /dev/mtd0 and then 8 blocks in /dev/mtd1 but that
did not seem to work.  (I am unsure if the lock property was present or not 
when I tried this.)
At any rate, it was simpler to expand mtd0 to the full range I wanted to lock.
Unfortunately this now moves all other mtd partitions down one.
For example, original mtd5 is now mtd4 when running this image.
The partition names are still accurate so you can look at /dev/mtd/by-name.

### Details of SRWD and W#

The SRWD bit was useful when we had only one pin and dual pin IO SPI-NOR parts.
On these parts the W# signal had a dedicated pin and could be tied / controlled
in HW.  So setting the SRWD bit would prevent any further updates unless a
jumper was installed (for example) to enable further writes.

Unfortunately, with the advent of QSPI, the W# signal is normally multiplexed
with one of the IO pins.  On the part used on the Kria SOM it is multiplexed
with DQ2.  If the QSPI part is used in 1 or 2 pin IO mode then the signal is
still useful. 
However, if all four IO pins are connected to a quad IO SPI controller,
as is the typical case and is the case on the Kria SOM, then the signal is
not very useful and can cause issues as described above.

Since DQ2/W# is connected to the SPI controller, it is susceptible to attacks.
A malicious kernel could do opcodes to tell the QSPI to operate in single pin IO
but keep the controller in 4 pin IO write mode.  In this way the user could
program the command sequence into DQ0 and manipulate DQ2 and DQ3 as they wish.

Current unknowns:
* Does the Kria SOM have a pull up or down on the DQ2/W# signal?
The data sheet suggests that it should.
* What is the state of DQ2 line from the SPI controller when in 1 or 2 pin
IO mode.  
  * Does it go Hi-Z? 
  * Is it pulled or driven one way or the other by the controller 
  * or by the IO pin control?
* What IO mode does the kernel use to do SR reads and writes? 
  * cat /sys/kernel/debug/spi-nor/spi0.0/params shows:
    * register protocol as 1S-1S-1S
    * read and write protocols are 1S-4S-4S
  * This suggests that SR reads and writes would be done in 1 bit single data
  per clock IO mode and the W# signal would be read from the DQ2/W# pin at
  that time
* How does the QSPI sample W# in 4 pin IO mode?
  * Is it always sampled as 1 or as 0?
  * Is it sampled as latched version of the W# signal before 4 pin IO mode was started?

**For all of these reasons, it is best to avoid all this and prevent SRWD
from being set, as this image/dtb does!**