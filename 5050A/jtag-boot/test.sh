#!/bin/bash

source common.sh

# try from cold boot
boardctl vpr_5050A off
echo "wait in poweroff"
sleep 20
boardctl vpr_5050A on
wait_ssh vpr-5050A
ssh vpr-5050A v2/load.sh mmc
echo "wait for arm boot"
sleep 40
# ping arm, won't work
test_ping $ARM_IP "from cold start" | tee -a results.txt


# try from warm boot
ssh -t vpr-5050A sudo shutdown -r now
echo "wait for shutdown to finish"
sleep 20
wait_ssh vpr-5050A
ssh vpr-5050A v2/load.sh mmc
echo "wait for arm boot"
sleep 40
# ping arm, should work
test_ping $ARM_IP "from warm start" | tee -a results.txt
test_ssh vpr-5050A-arm "from warm start" | tee -a results.txt

# clean power off for next time
ssh -t vpr-5050A sudo shutdown now
echo "wait for shutdown to finish"
sleep 30
boardctl vpr_5050A off


