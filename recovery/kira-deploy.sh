#!/bin/sh
# This runs on host and on target so needs to use /bin/sh NOT /bin/bash
# Target side runs in busybox ash so avoid bash'isums

# Deploy assets to a Xilinx Kira board
# Also acts as kira-update-recovery if used with that name

ME_DIR=$(dirname $(readlink -f $0))
ME_BASE=$(basename $0)
ME=${ME_DIR}/${ME_BASE}
DEV_IP=$1
WHERE=$2

BLOCK_SIZE_MEG=64
BLOCK_SIZE="${BLOCK_SIZE_MEG}M"
BLOCK_SIZE_FULL="$(( $BLOCK_SIZE_MEG * 1024 * 1024 ))"
USER=root

ssh_rekey() {
    # check board is alive at IP_ADDR
    if ! ping -c 1 ${DEV_IP}; then
        echo "Board at ${DEV_IP} does not repsond to ping"
        exit 3
    fi

    # recovey has a new SSH machine ID each time, re-prime
    ssh-keygen -R ${DEV_IP}
    ssh -o StrictHostKeyChecking=no ${USER}@${DEV_IP} true
}

do_on_target() {
    export PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin"
    BOOT_DONE=false

    if [ -r ImageA.bin ]; then
        echo "Update Boot Image A"
        flash_erase /dev/mtd5 0 0
        dd if=ImageA.bin of=/dev/mtd5 bs=64k
        BOOT_DONE=true
    fi

    if [ -r ImageB.bin ]; then
        echo "Update Boot Image B"
        flash_erase /dev/mtd7 0 0
        dd if=ImageB.bin of=/dev/mtd7 bs=64k
        BOOT_DONE=true
    fi

    if ! $BOOT_DONE; then 
        for f in ImageAB.bin BOOT.BIN boot.bin; do
            if [ -r $f ]; then
                echo "Update Boot Image A with $f"
                flash_erase /dev/mtd5 0 0
                dd if=$f of=/dev/mtd5 bs=64k

                echo "Update Boot Image B with $f"
                flash_erase /dev/mtd7 0 0
                dd if=$f of=/dev/mtd7 bs=64k

                BOOT_DONE=true
                break
            fi
        done
    fi

    if [ -r u-boot-vars2.bin ]; then
        VARS2_DONE=true
        echo "Update 2nd copy of U-boot vars (NON-UEFI)"
        flash_erase /dev/mtd12 0 0
        dd if=u-boot-vars2.bin of=/dev/mtd12 bs=64k
    else
        VARS2_DONE=false
    fi

    if [ -r u-boot-vars.bin ]; then
        echo "Update U-boot vars (NON-UEFI)"
        flash_erase /dev/mtd11 0 0
        dd if=u-boot-vars2.bin of=/dev/mtd11 bs=64k

        if ! $VARS2_DONE; then
            echo "Update 2nd copy"
            flash_erase /dev/mtd12 0 0
            dd if=u-boot-vars.bin of=/dev/mtd12 bs=64k
        fi
    fi

    if [ -r sel-reg.bin ]; then
        echo "Update IMGSEL variables"
        flash_erase /dev/mtd2 0 0
        dd if=sel-reg.bin of=/dev/mtd2 bs=64k

        echo "Update 2nd copy"
        flash_erase /dev/mtd3 0 0
        dd if=sel-reg.bin of=/dev/mtd3 bs=64k
    fi
}

do_on_target_chunk() {
    DEV="/dev/$1"
    FILE=$2
    BLOCK=$3

    #echo "Chunk $DEV $FILE $BLOCK"
    
    if [ ! -e $DEV ]; then
        echo "ERROR: /dev/$DEV does not exist"
        exit 5
    fi

    dd if=$DEV  of=chunk.bin bs=$BLOCK_SIZE skip=$BLOCK count=1 >/dev/null 2>&1
    if ! cmp $FILE chunk.bin >/dev/null 2>&1 ; then
        dd if=$FILE of=$DEV bs=$BLOCK_SIZE seek=$BLOCK >/dev/null 2>&1
        sync
        echo -n "*"
    else
        echo -n "."
    fi
    rm $FILE
}

do_host_big_file() {
    FILE=$1
    TEMPDIR=$(mktemp -d)
    ASSETS_DIR=$(readlink -f .)

    case $FILE in
    usb.img*)
        DEV=sda
        BASE=usb.img
        ;;
    emmc.img*)
        DEV=mmcblk0
        BASE=emmc.img
        ;;
    sd.img*)
        DEV=mmcblk1
        BASE=sd.img
        ;;
    *)
        echo "unknown device for $FILE"
    esac

    echo "TEMPDIR=$TEMPDIR DEV=$DEV FILE=$FILE BLOCK_SIZE=$BLOCK_SIZE"

    FILE_EXT=$(echo $FILE | sed -e "s/^$BASE//")
    FULL_FILE=$TEMPDIR/$BASE
    case $FILE_EXT in
    "")
        # do nothing, use file as is
        true
        FULL_FILE=$ASSETS_DIR/$FILE
        ;;
    .gz)
        echo "decompressing $FILE"
        zcat $FILE >$FULL_FILE
        ;;
    .bz2)
        echo "decompressing $FILE"
        bzcat $FILE >$FULL_FILE
        ;;
    .xz)
        echo "decompressing $FILE"
        xzcat $FILE >$FULL_FILE
        ;;
    *)
        echo "unknown compression extension $FILE_EXT for $FILE"
        exit 4
    esac

    cd $TEMPDIR
    echo "splitting $BASE into $BLOCK_SIZE chunks"
    split --bytes=$BLOCK_SIZE -d $FULL_FILE $BASE-
    echo "processing chunks:"
    LAST=false
    for f in $BASE-*; do
        if $LAST; then
            echo "Error: $LAST_FILE was not $BLOCK_SIZE and was not last file"
            exit 4
        fi

        BLOCK=$(echo $f | sed -e "s#^${BASE}-##")

        # coreutils split (version 8.30-3ubuntu2)
        # uses strange numerical sequences
        # 00 to 89, 9000 to 989, 990000 to unknown
        if [ $BLOCK -gt 989999 ]; then
            BLOCK=$(( $BLOCK - 990000 + 990 ))
        elif [ $BLOCK -gt 8999 ]; then
            BLOCK=$(( $BLOCK - 9000 + 90 ))
        fi

        CHUNK_SIZE=$(stat -t $f | cut -d' ' -f2)
        if [ $CHUNK_SIZE -ne $BLOCK_SIZE_FULL ]; then
            dd if=/dev/zero of=${f}.pad bs=$BLOCK_SIZE count=1 >/dev/null 2>&1
            dd if=$f of=${f}.pad conv=notrunc >/dev/null 2>&1
            LAST=true;
            LAST_FILE=$f
            f=${f}.pad
        fi

        #echo "f=$f BLOCK=$BLOCK"
        scp $f ${USER}@${DEV_IP}: >/dev/null 
        ssh ${USER}@${DEV_IP} ./${ME_BASE} on_target_chunk $DEV $f $BLOCK
    done

    echo ""
    echo "DONE $BASE"

    rm $BASE-*
    rm $BASE >/dev/null 2>&1 || true
    cd $ASSETS_DIR
    rmdir $TEMPDIR
}

do_on_host() {
    ANY=false
    ANY_MTD=false
    DEF_SEL_REG=${ME_DIR}/sel-reg-ImageA.bin

    if [ -n "$WHERE" ]; then
        cd $WHERE
    fi

    ssh_rekey

    for f in ./sd.img ./emmc.img ./usb.img; do
        for c in "" .gz .bz2 .xz; do
            if [ -r ${f}${c} ]; then
                ANY=true
                break
            fi
        done
    done

    # transfer all recovery assets to DUT
    for f in ./ImageA.bin ./ImageB.bin ./ImageAB.bin ./BOOT.BIN ./boot.bin \
             ./u-boot-vars.bin ./u-boot-vars2.bin; do
        if [ -r $f ]; then
            #echo "Transfer $f"
            scp $f ${USER}@${DEV_IP}:
            ANY_MTD=true
            ANY=true
        fi
    done

    # if an explicit img-sel.bin is given, use it
    if [ -r ./sel-reg.bin ]; then
            scp ./sel-reg.bin ${USER}@${DEV_IP}:
            ANY=true
            ANY_MTD=true
    elif $ANY_MTD; then
        # otherwise use the default if any mtd partitions are being updated
        if [ ! -r ${DEF_SEL_REG} ]; then
            echo "error: default imgsel settings file ${DEF_SEL_REG} not found"
            exit 2
        fi
        scp ${DEF_SEL_REG} ${USER}@${DEV_IP}:sel-reg.bin
    fi

    if ! $ANY; then
        echo "No deployment assets found!"
        exit 4
    fi
    
    # copy this script to the DUT
    #echo "Transfer ${ME}"
    scp ${ME} ${USER}@${DEV_IP}:

    # now execute on DUT
    # return code is whatever subscript returns
    if $ANY_MTD; then
        ssh ${USER}@${DEV_IP} ./${ME_BASE} on_target
    fi

    for f in ./sd.img ./emmc.img ./usb.img; do
        for c in "" .gz .bz2 .xz; do
            if [ -r ${f}${c} ]; then
                do_host_big_file $(basename ${f}${c})
                break
            fi
        done
    done
}


do_help() {
    echo "kira-deploy: update software for testing of a given Xilinx Kira board"
    echo "kira-depoly device-ip [asset-dir]"
    echo "handles:"
    echo "    ImageA.bin and/or ImageB.bin, updates specific boot image in QSPI"
    echo "        if neither of these if found:"
    echo "        ImageAB.bin, BOOT.BIN or boot.bin,"
    echo "            updates BOTH boot images in QSPI"
    echo "    sd.img{,.gz,.bz2,.xz}   writes to SD card"
    echo "    emmc.img{,.gz,.bz2,.xz} writes to the user portion of emmc"
    echo "    usb.img{,.gz,.bz2,.xz}  writes to the first USB storage (/dev/sda)"
    echo "less common:"
    echo "    u-boot-vars.bin  written to mtd12"
    echo "        also written to mts13 unless below file is present"
    echo "    u-boot-vars2.bin written to mtd13"
    echo "    Note: a zero length file for any QSPI area effectively erases it"
    echo "    "
    echo "    sel-reg.bin an explicit value for the imgsel settings partitions"
    echo "    If any boot image is given and this file is not given,"
    echo "        then a default image is used that sets A as the active image"
    echo "    both mtd2 and mtd3 are written"
    exit 2
}

#echo "ME_BASE=$ME_BASE CMD_EXTRA=$CMD_EXTRA"

case ${DEV_IP} in
on_target*)
    shift
    do_${DEV_IP} "$@"
    ;;
"")
    do_help
    ;;
*)
    do_on_host
    ;;
esac
