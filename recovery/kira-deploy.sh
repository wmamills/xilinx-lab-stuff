#!/bin/sh
# This runs on host and on target so needs to use /bin/sh NOT /bin/bash
# Target side runs in busybox ash so avoid bash'isums

# Deploy assets to a Xilinx Kira board

ME=$(readlink -f $0)
ME_BASE=$(basename $ME)
DEV_IP=$1
WHERE=$2

BLOCK_SIZE_MEG=8
BLOCK_SIZE="${BLOCK_SIZE_MEG}M"
BLOCK_SIZE_FULL="$(( $BLOCK_SIZE_MEG * 1024 * 1024 ))"
USER=root

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
        for f in BOOT.BIN boot.bin; do
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
    usb.img)
        DEV=sda
        ;;
    emmc.img)
        DEV=mmcblk0
        ;;
    sd.img)
        DEV=mmcblk1
        ;;
    *)
        echo "unknown device for $FILE"
    esac

    echo "TEMPDIR=$TEMPDIR DEV=$DEV FILE=$FILE BLOCK_SIZE=$BLOCK_SIZE"

    cd $TEMPDIR
    split --bytes=$BLOCK_SIZE -d $ASSETS_DIR/$FILE $FILE-
    for f in $FILE-*; do
        BLOCK=$(echo $f | sed -e "s#^${FILE}-##")

        # coreutils split (version 8.30-3ubuntu2)
        # uses strange numerical sequences
        # 00 to 89, 9000 to 989, 990000 to unknown
        if [ $BLOCK -gt 989999 ]; then
            BLOCK=$(( $BLOCK - 990000 + 990 ))
        elif [ $BLOCK -gt 8999 ]; then
            BLOCK=$(( $BLOCK - 9000 + 90 ))
        fi

        #echo "f=$f BLOCK=$BLOCK"
        scp $f root@$DEV_IP: >/dev/null 
        ssh root@$DEV_IP ./$ME_BASE on_target_chunk $DEV $f $BLOCK
    done

    echo ""
    echo "DONE $FILE"

    rm $FILE-*
    cd $ASSETS_DIR
    rmdir $TEMPDIR
}

do_on_host() {
    ANY=false

    if [ -n "$WHERE" ]; then
        cd $WHERE
    fi
    # check board is alive at IP_ADDR
    if ! ping -c 1 $DEV_IP; then
        echo "Board at $DEV_IP does not repsond to ping"
        exit 3
    fi

    # recovey has a new SSH machine ID each time, re-prime
    ssh-keygen -R $DEV_IP
    ssh -o StrictHostKeyChecking=no root@192.168.157.43 true

    # transfer all recovery assets to DUT
    for f in ./ImageA.bin ./ImageB.bin ./BOOT.BIN /.boot.bin ./u-boot-vars.bin ./u-boot-vars2.bin; do
        if [ -r $f ]; then
            #echo "Transfer $f"
            scp $f root@$DEV_IP:
            ANY=true
        fi
    done

    for f in ./sd.img ./emmc.img ./usb.img; do
        if [ -r $f ]; then
            ANY=true
        fi
    done

    if ! $ANY; then
        echo "No deployment assets found!"
        exit 4
    fi
    
    # copy this script to the DUT
    #echo "Transfer $ME"
    scp $ME root@$DEV_IP:

    # now execute on DUT
    # return code is whatever subscript returns
    ssh root@$DEV_IP ./$(basename $ME) on_target

    for f in ./sd.img ./emmc.img ./usb.img; do
        if [ -r $f ]; then
            do_host_big_file $(basename $f)
        fi
    done
}


do_help() {
    echo "kira-update-recovery: update the recovery assets of a given Xilinx Kira board"
    echo "kira-update-recovery device-ip [asset-dir]"
    exit 2
}


case $DEV_IP in
on_target*)
    shift
    do_$DEV_IP "$@"
    ;;
"")
    do_help
    ;;
*)
    do_on_host
    ;;
esac
