#!/bin/bash

source common.sh

while true; do
    wait_ping $X86_IP
    wait_ssh vpr-5050A
    ssh -t vpr-5050A screen /dev/ttyUSB1 115200
    echo sleeping for 10 seconds before trying again
    sleep 10
done

