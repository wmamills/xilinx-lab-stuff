#!/bin/bash

ORIGDIR=$(pwd)
ME=$0
ACTION=$1

# error out on any unexpected failure
set -e

: ${DEBUG:=false}

abort() {
    echo "ERROR: $@"
    exit 2
}

do_fr_initrd() {
    TEMPDIR=$(mktemp -d)
    mkdir $TEMPDIR/initrd
    tar -C $TEMPDIR/initrd -xf core-image-minimal-zynqmp-production.tar.gz
    cp -a rootfs-hacks/* $TEMPDIR/initrd/
    (cd $TEMPDIR/initrd; \
        find . | cpio --quiet -H newc -o \
        | gzip -9 -n > $ORIGDIR/core-min.cpio.gz)
    rm -rf $TEMPDIR/initrd
    rmdir $TEMPDIR
}

do_initrd() {
    fakeroot bash $ME fr_initrd
}

do_default() {
    mkimage -f recovery-fit.its recovery.fit
    mkimage -T script -d recovery-script.txt recovery-script.scr
    mkimage -T script -d recovery-update-script.txt recovery-update-script.scr
    mkimage -T script -d recovery-boot-script.txt recovery-boot-script.scr
}

do_sudo_sdcard() {
    SDIMG_FILE=$1
    SCRIPT_FILE=$2
    VFAT=$(pwd)

    KPART_OUT=$(kpartx -avs $SDIMG_FILE | head -n 1 | cut -d ' ' -f 3)
    export LOOPDEV=${KPART_OUT%%p1}
    trap "cleanup_sdimg_priv $SDIMG_FILE $LOOPDEV; exit 255" INT TERM EXIT

    test -b /dev/mapper/${LOOPDEV}p1 || abort "${LOOPDEV}p1 does not exist"

    mkfs.vfat -n boot /dev/mapper/${LOOPDEV}p1
    mkdir -p /media/${LOOPDEV}p1
    mount /dev/mapper/${LOOPDEV}p1 /media/${LOOPDEV}p1

    B=/media/${LOOPDEV}p1

    echo "populate boot partition"
    cp    --preserve=timestamps $VFAT/$SCRIPT_FILE $B/boot.scr
    for f in recovery-boot.bin recovery.fit recovery-script.scr; do
        cp    --preserve=timestamps $VFAT/$f $B
    done

    sync

    if $DEBUG; then
        echo "check it out before I unmount"
        echo "make sure to exit the dirs before you continue"
        echo "hit return to continue"
        read
        sync
    fi

    trap - INT TERM EXIT
    cleanup_sdimg_priv $SDIMG_FILE $LOOPDEV
}

cleanup_sdimg_priv() {
    SDIMG_FILE=$1
    LOOPDEV=$2

    umount /dev/mapper/${LOOPDEV}p1
    kpartx -dv $SDIMG_FILE
}

do_one_sdcard() {
    SDIMG_FILE=$1
    SCRIPT_FILE=$2

    dd if=/dev/zero of=$SDIMG_FILE bs=1M count=64
    cat sd-full-vfat.sfdisk | /sbin/sfdisk $SDIMG_FILE

    echo "This will require sudo"
    if ! sudo $ME sudo_sdcard $SDIMG_FILE $SCRIPT_FILE; then
        rm $SDIMG_FILE
        abort "can't get sudo or image creation failed"
    fi

    if [ -f $SDIMG_FILE.bz2 ]; then
        DATE=$(date --date=@$(stat -c%Y $SDIMG_FILE.bz2) +%Y-%m-%d-%H%M%S)
        mv $SDIMG_FILE.bz2 $SDIMG_FILE.bz2.$DATE
    fi
    echo "compressing image $SDIMG_FILE"
    bzip2 $SDIMG_FILE
}

do_sdcard() {
    do_one_sdcard recovery-update-sdcard.img recovery-update-script.scr
    do_one_sdcard recovery-boot-sdcard.img   recovery-boot-script.scr
}

do_all() {
    do_initrd
    do_default
    do_sdcard
}

case ${ACTION} in
"")
    do_default
    ;;
*)
    shift
    do_${ACTION} "$@"
    ;;
esac
