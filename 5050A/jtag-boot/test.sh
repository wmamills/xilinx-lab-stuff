#!/bin/bash

source common.sh

# pre-boot
boardctl vpr_5050A off
echo "wait in poweroff"
sleep 20
boardctl vpr_5050A on
wait_ssh vpr-5050A
ssh vpr-5050A v2/load.sh none
echo "wait for u-boot to run"
sleep 10

# now do warm boot so arm can boot all the way
ssh -t vpr-5050A sudo shutdown -r now
echo "wait for shutdown to finish"
sleep 20
wait_ssh vpr-5050A
ssh vpr-5050A v2/load.sh mmc
echo "wait for arm boot"
wait_ssh vpr-5050A-arm
echo "Start QEMU on arm"
ssh vpr-5050A-arm ./run-versal-virtio-msg-net-backend.sh
echo "Wait for debug"
sleep 10

# warm boot so x86 can get in sync
ssh -t vpr-5050A sudo shutdown -r now
echo "wait for shutdown to finish"
sleep 20
wait_ssh vpr-5050A
echo "Start X86 drivers"
ssh -t vpr-5050A ./run-x86-virtio-msg-net-frontend.sh

if ssh vpr-5050A ping -c 3 192.168.17.1; then
    echo "Ping from x86 to arm OK" | tee -a results.txt
else
    echo "Ping from x86 to arm FAILED" | tee -a results.txt
fi

if ssh vpr-5050A-arm ping -c 3 192.168.17.2; then
    echo "Ping from arm to x86 OK" | tee -a results.txt
else
    echo "Ping from arm to x86 FAILED" | tee -a results.txt
fi

# clean power off for next time
ssh vpr-5050A-arm poweroff
ssh -t vpr-5050A sudo shutdown now
echo "wait for shutdown to finish"
sleep 20
boardctl vpr_5050A off


