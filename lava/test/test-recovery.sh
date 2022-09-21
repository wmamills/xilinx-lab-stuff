#!/bin/bash

set -x

IP=192.168.2.199
MY_DIR=$(dirname $(readlink -f $0))
ULB=/usr/local/bin/

${ULB}relayctl relay3 1 off
${ULB}relay3 2 on
sleep 5
${ULB}relayctl relay3 1 on
sleep 30
if ping -c 1 $IP; then
    echo "WORKS"
    ${ULB}kria-deploy.sh $IP $MY_DIR
else
    echo "BROKEN"
fi
${ULB}relayctl relay3 1 off
${ULB}relayctl relay3 2 off
