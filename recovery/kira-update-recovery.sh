#!/bin/sh

# Program or update the recovery assets of a Xilinx Kira board
# This is only possible on a board using the Production SOM
# NOT the starter SOM that kv260 and kr260 come with

ME=$0
DEV_IP=$1
WHERE=$2

do_on_target() {
    export PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin"

    if [ -r recovery.fit ]; then
        echo "Update recovery.fit"
        # erase main part of mtd15 after first 3 64k sectors
        # first 3 sectors are locked for some reason (mistake?)
        flash_erase /dev/mtd15 0x30000 448
        dd if=recovery.fit of=/dev/mtd15 bs=64k seek=3
    fi

    if [ -r recovery-script.scr ]; then
        echo "Update recovery-script.scr"
        # last 0x18_0000 bytes of flash are script area 
        # defined in upstream u-boot's bootcmd_qspi0
        flash_erase /dev/mtd15 0x01c30000 0
        dd if=recovery-script.scr of=/dev/mtd15 bs=64k seek=451
    fi

    if [ -r recovery-boot.bin ]; then
        echo "Update recovery-boot.bin"
        # update the recovey-u-boot images
        flash_erase /dev/mtd10 0 0
        dd if=recovery-boot.bin of=/dev/mtd10 bs=64k
        flash_erase /dev/mtd11 0 0
        dd if=recovery-boot.bin of=/dev/mtd11 bs=64k
    fi
}

do_on_host() {
    ANY=false

    # check board is alive at IP_ADDR
    if ! ping -c 1 $DEV_IP; then
        echo "Board at $DEV_IP does not repsond to ping"
        exit 3
    fi

    # recovey has a new SSH machine ID each time, re-prime
    ssh-keygen -R $DEV_IP
    ssh -o StrictHostKeyChecking=no root@192.168.157.43 true

    # transfer all recovery assets to DUT
    for f in ./recovery-boot.bin recovery.fit recovery-script.scr; do
        if [ -r $f ]; then
            #echo "Transfer $f"
            scp $f root@$DEV_IP:
            ANY=true
        fi
    done

    if ! $ANY; then
        echo "No recovery assets found!"
        exit 4
    fi
    
    # copy this script to the DUT
    #echo "Transfer $ME"
    scp $ME root@$DEV_IP:

    # now execute on DUT
    # return code is whatever subscript returns
    ssh root@$DEV_IP ./$(basename $ME) on_target
}

do_help() {
    echo "kira-update-recovery: update the recovery assets of a given Xilinx Kira board"
    echo "kira-update-recovery device-ip [asset-dir]"
    exit 2
}

if [ -n "$WHERE" ]; then
    cd $WHERE
fi

if [ x"$DEV_IP" == x"on_target" ]; then
    do_on_target
elif [ -n "$DEV_IP" ]; then
    do_on_host
else
    do_help
fi
