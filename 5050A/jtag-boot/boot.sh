#!/bin/bash

source common.sh

# pre-boot
boardctl vpr_5050A on
wait_ssh vpr-5050A
ssh vpr-5050A v2/load.sh none
echo "wait for arm u-boot"
sleep 5


# try from warm boot
ssh -t vpr-5050A sudo shutdown -r now
echo "wait for shutdown to finish"
sleep 10
wait_ssh vpr-5050A
ssh vpr-5050A v2/load.sh mmc
echo "wait for arm boot"
wait_ssh vpr-5050A-arm


