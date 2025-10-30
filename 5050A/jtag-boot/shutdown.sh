#!/bin/bash

source common.sh

# clean power off for next time
ssh -t vpr-5050A sudo shutdown now
echo "wait for shutdown to finish"
sleep 10
boardctl vpr_5050A off


