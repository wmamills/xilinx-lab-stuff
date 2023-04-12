#!/bin/bash

ORIGDIR=$(pwd)
ME=$0
ACTION=$1

BOARD=zcu102
CPIO_FILE_IN=petalinux-image-minimal-zcu102-zynqmp.cpio.gz
CPIO_FILE=petalinux-hacked-image-min-zcu102.cpio.gz

# error out on any unexpected failure
set -e

: ${DEBUG:=false}

if $DEBUG; then
    set -x
fi

abort() {
    echo "ERROR: $@"
    exit 2
}

do_fr_initrd() {
    TEMPDIR=$(mktemp -d)
    mkdir $TEMPDIR/initrd

    echo "extracting $CPIO_FILE_IN"
    (cd $TEMPDIR/initrd; zcat $ORIGDIR/$CPIO_FILE_IN | cpio -id )

    # give shadow the correct permissions regardless of what git does
    chmod 400 rootfs-hacks/etc/shadow
    cp -a rootfs-hacks/* $TEMPDIR/initrd/

    echo "rearchiving to $CPIO_FILE"
    (cd $TEMPDIR/initrd; \
        find . | cpio --quiet -H newc -o \
        | gzip -9 -n > $ORIGDIR/$CPIO_FILE)

    rm -rf $TEMPDIR/initrd
    rmdir $TEMPDIR
}

do_initrd() {
    fakeroot bash $ME fr_initrd
}

do_default() {
    for i in tftp vfat_initrd ext4; do
        mkimage -T script -d boot-${i}.txt boot-${i}.scr
    done
}

do_sudo_tftp() {
    echo "nothing else needed"
}

do_sudo_vfat_initrd() {
    echo "populate boot partition"
    for f in \
        Image-zcu102-zynqmp.bin \
        $CPIO_FILE \
        system.dtb; do
        cp    --preserve=timestamps $SRC/$f $B
    done
}

do_sudo_ext4() {
    echo "populate root partition"

    if [ ! -d $R ]; then
        echo "No 2nd partition, fail"
        false
    fi

    # extract initrd image
    echo "extracting $CPIO_FILE to rootfs"
    (cd $R; zcat $SRC/$CPIO_FILE | cpio -id )

    mkdir -p $R/boot
    for f in \
        Image-zcu102-zynqmp.bin \
        system.dtb; do
        echo "copy $f to /boot on rootfs"
        cp    --preserve=timestamps $SRC/$f $R/boot
    done
}

do_sudo_sdcard() {
    SDIMG_FILE=$1
    SCRIPT_NAME=$2
    SRC=$(pwd)

    KPART_OUT=$(kpartx -avs $SDIMG_FILE | head -n 1 | cut -d ' ' -f 3)
    export LOOPDEV=${KPART_OUT%%p1}
    trap "cleanup_sdimg_priv $SDIMG_FILE $LOOPDEV; exit 255" INT TERM EXIT

    test -b /dev/mapper/${LOOPDEV}p1 || abort "${LOOPDEV}p1 does not exist"

    mkfs.vfat -n boot /dev/mapper/${LOOPDEV}p1
    mkdir -p /media/${LOOPDEV}p1
    mount /dev/mapper/${LOOPDEV}p1 /media/${LOOPDEV}p1

    B=/media/${LOOPDEV}p1

    if test -b /dev/mapper/${LOOPDEV}p2; then
        mkfs.ext4 -L rootfs /dev/mapper/${LOOPDEV}p2
        mkdir -p /media/${LOOPDEV}p2
        mount /dev/mapper/${LOOPDEV}p2 /media/${LOOPDEV}p2

        R=/media/${LOOPDEV}p2
    else
        echo "No 2nd partition"
        R=""
    fi

    # Add boot.bin and boot script to boot partition
    echo "copy BOOT-zcu102-zynqmp.bin as boot.bin to boot partition"
    cp    --preserve=timestamps $SRC/BOOT-zcu102-zynqmp.bin  $B/boot.bin
    echo "copy boot-${SCRIPT_NAME}.scr as boot.scr to boot partition"
    cp    --preserve=timestamps $SRC/boot-${SCRIPT_NAME}.scr $B/boot.scr
    do_sudo_${SCRIPT_NAME}

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

    cd /
    for i in 1 2 3; do
        for b in /dev/mapper/${LOOPDEV}p*; do
            if [ -b $b ]; then
                echo "($i) umount & remove $b"
                umount $b || true
                dmsetup remove $b || true
            fi
        done

        # once allocated the loopdev seems to always exist
        # so instead ask losetup if there is a file associated
        if losetup /dev/${LOOPDEV} >/dev/null 2>&1; then
            echo "($i) unloop $/dev/${LOOPDEV}"
            losetup -d /dev/${LOOPDEV} || true
        fi

        if losetup /dev/${LOOPDEV} >/dev/null 2>&1; then
            echo "($i) /dev/${LOOPDEV} is still mapped, sleeping"
            sync; sync; sleep 10
        else
            break
        fi
    done

    # this does not seem to work so I went to dmsetup and losetup directly
    #kpartx -dv $SDIMG_FILE
}

do_one_sdcard() {
    IMG_NAME=$1
    SDIMG_SIZE=$2
    LAYOUT_FILE=$3

    SDIMG_FILE=${BOARD}-${IMG_NAME}.img

    dd if=/dev/zero of=$SDIMG_FILE bs=1M count=$SDIMG_SIZE
    cat $LAYOUT_FILE | /sbin/sfdisk $SDIMG_FILE

    echo "This will require sudo"
    if ! sudo $ME sudo_sdcard $SDIMG_FILE $IMG_NAME; then
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

do_tftp() {
    do_one_sdcard tftp          16      sd-full-vfat.sfdisk
}

do_vfat_initrd() {
    do_one_sdcard vfat_initrd   128     sd-full-vfat.sfdisk
}

do_ext4() {
    do_one_sdcard ext4          1024    sd-vfat-ext4.sfdisk
}

do_sdcard() {
    do_tftp
    do_vfat
    do_ext4
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
