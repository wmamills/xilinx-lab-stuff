#!/bin/sh
# This runs on host and on target so needs to use /bin/sh NOT /bin/bash
# Target side runs in busybox ash so avoid bash'isums

# Deploy assets to a Xilinx Kria board

ME_DIR=$(dirname $(readlink -f $0))
ME_BASE=$(basename $0)
ME=${ME_DIR}/${ME_BASE}

BLOCK_SIZE_MEG=64
BLOCK_SIZE="${BLOCK_SIZE_MEG}M"
BLOCK_SIZE_FULL="$(( $BLOCK_SIZE_MEG * 1024 * 1024 ))"
USER=root

# recovery has a new SSH machine ID each time, disable know_hosts
SSH_OPTION="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

set -e

ssh_rekey() {
    # check board is alive at IP_ADDR
    echo "Check that board at ${DEV_IP} is alive"
    TIMEOUT=60
    COUNT=0
    while ! ping -c 1 ${DEV_IP} >/dev/null; do
        if [ $COUNT -gt $TIMEOUT ]; then
            echo "Board at ${DEV_IP} does not repsond to ping"
            exit 3
        fi
        echo -n "."
        sleep 1
        COUNT=$(( COUNT + 1 ))
    done
    echo "Board at ${DEV_IP} is alive"

    # we are not doing known_host's anymore so we don't need this
    # ssh-keygen -R ${DEV_IP}

    TIMEOUT=60
    COUNT=0
    while ! ssh $SSH_OPTION ${USER}@${DEV_IP} true >/dev/null 2>&1; do
        if [ $COUNT -gt $TIMEOUT ]; then
            echo "Can't ssh into Board at ${DEV_IP}"
            exit 3
        fi
        echo -n "."
        sleep 1
        COUNT=$(( COUNT + 1 ))
    done
    echo "Board at ${DEV_IP} ready"
}

# Newer versions of openssh-client's scp command use sftp-server
# dropbear does not support that, use -O to use the old method
# However older versions of openssh-client do not support -O
# New default ~= 9.2 in debian 12 bookworm
# -O supported but new not default, 8.9 Ubuntu 22.04
# Old ~= 8.2 in Ubuntu 20.04, 8.4 in debian 11 bullseye
scp_setup() {
    if scp -O 2>&1 | grep "unknown option" >/dev/null; then
        SCP_OPTION=""
    else
        SCP_OPTION="-O"
        echo "Using -O option for scp"
    fi
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
        dd if=u-boot-vars.bin of=/dev/mtd11 bs=64k

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
        scp $SCP_OPTION $SSH_OPTION $f ${USER}@${DEV_IP}: >/dev/null 
        ssh $SSH_OPTION ${USER}@${DEV_IP} ./${ME_BASE} on_target_chunk $DEV $f $BLOCK
    done

    echo ""
    echo "DONE $BASE"

    rm $BASE-*
    rm $BASE >/dev/null 2>&1 || true
    cd $ASSETS_DIR
    rmdir $TEMPDIR
}

do_on_host() {
    DEV_IP=$1
    WHERE=$2

    ANY=false
    ANY_MTD=false
    DEF_SEL_REG=${ME_DIR}/sel-reg-ImageA.bin

    if [ -n "$WHERE" -a -d "$WHERE" ]; then
        cd $WHERE
        shift 2
    else
        echo "Error: 2nd argument should be a directory where the assets are"
        echo "       if you want to use the current directory use . "
        exit 2
    fi

    # look for directories (from LAVA deploy images: for example)
    # First look for MTD (.bin) files
    for i in ImageA ImageB ImageAB boot sel-reg u-boot-vars u-boot-vars2; do
        if [ ! -d $i ]; then continue; fi
        if [ -e $i.bin ]; then
            echo "Warning: ignoring directory $i as $i.bin already exists"
            continue
        fi
        FOUND=""
        for f in $i/*.bin; do
            # ignore non matching wild cars
            if [ ! -e $f ]; then continue; fi
            if [ -n "$FOUND" ]; then
                echo "There were too many *.bin files in $i"
                echo "Found at least $FOUND and $i/$f"
                FOUND=""
                break
            fi
            FOUND=$f
        done
        if [ -n "$FOUND" ]; then
            ln -s $FOUND $i.bin
            echo "Created symlink: $(ls -l $i.bin)"
        else
            echo "WARNING: no %i.bin found/used"
        fi
    done

    # now look for disk images
    for i in sd emmc usb; do
        if [ ! -d $i ]; then continue; fi
        if [ -e $i.img ]; then
            echo "Warning: ignoring directory $i as $i.img already exists"
            continue
        fi
        FOUND=""
        for f in $i/*.img $i/*.wic; do
            # ignore non matching wild cars
            if [ ! -e $f ]; then continue; fi
            #echo "f=$f FOUND=|$FOUND|"
            if [ -n "$FOUND" ]; then
                echo "There were too many disk image files in $i"
                echo "Found at least $FOUND and $f"
                FOUND=""
                break
            fi
            FOUND=$f
        done
        if [ -n "$FOUND" ]; then
            ln -s $FOUND $i.img
            echo "Created symlink: $(ls -l $i.img)"
        else
            echo "WARNING: no $i.img found/used"
        fi
    done

    scp_setup
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
            scp $SCP_OPTION $SSH_OPTION $f ${USER}@${DEV_IP}:
            ANY_MTD=true
            ANY=true
        fi
    done

    # if an explicit sel-bin.bin is given, use it
    if [ -r ./sel-reg.bin ]; then
            scp $SCP_OPTION $SSH_OPTION ./sel-reg.bin ${USER}@${DEV_IP}:
            ANY=true
            ANY_MTD=true
    elif $ANY_MTD; then
        # otherwise use the default if any mtd partitions are being updated
        if [ ! -r ${DEF_SEL_REG} ]; then
            echo "error: default imgsel settings file ${DEF_SEL_REG} not found"
            exit 2
        fi
        scp $SCP_OPTION $SSH_OPTION ${DEF_SEL_REG} ${USER}@${DEV_IP}:sel-reg.bin
    fi

    if ! $ANY; then
        echo "No deployment assets found!"
        exit 4
    fi
    
    # copy this script to the DUT
    #echo "Transfer ${ME}"
    scp $SCP_OPTION $SSH_OPTION ${ME} ${USER}@${DEV_IP}:

    # now execute on DUT
    # return code is whatever subscript returns
    if $ANY_MTD; then
        ssh $SSH_OPTION ${USER}@${DEV_IP} ./${ME_BASE} on_target
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
    echo "kria-deploy: update software for testing of a given Xilinx Kria board"
    echo "kria-depoly device-ip asset-dir"
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
    echo "lava deploy to flasher support"
    echo "    the deploy section can contain the list images:"
    echo "    each image goes into a directory of the same name"
    echo "    use image names of:"
    echo "       ImageA ImageB boot sel-reg u-boot-vars u-boot-vars2"
    echo "       sd emmc usb"
    echo "   each directory should only contain 1 file of the specified type"
    echo "       mtd items look for *.bin"
    echo "   disk images look for *.img or *.wic"
    echo "       (decompression should happen in lava)"
    echo "   only supply the image names for what you want to update"
    echo "   any existing files or symlinks in the base directory take precedence"
    exit 2
}

#echo "ME_BASE=$ME_BASE CMD_EXTRA=$CMD_EXTRA"

ACTION=$1
case ${ACTION} in
on_target*)
    shift
    do_${ACTION} "$@"
    ;;
"")
    do_help
    ;;
*)
    do_on_host "$@"
    ;;
esac
