#!/bin/bash

MY_DIR=$(cd $(dirname $0); pwd)
cd $MY_DIR

PATH=/tools/Xilinx/Vivado_Lab/2024.2/bin:$PATH

if [ -z "$1" ]; then
    BOOT_SCRIPT=boot-mmc.scr
elif [ -r $1 ]; then
    BOOT_SCRIPT=$1
elif [ -r boot-${1}.scr ]; then
    BOOT_SCRIPT="boot-${1}.scr"
else
    echo "Unknown boot mode $1"
    exit 2
fi


xsdb jtag-boot.tcl $BOOT_SCRIPT
