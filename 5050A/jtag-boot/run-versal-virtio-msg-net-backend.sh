#!/bin/sh

set -x

nohup ./qemu-system-aarch64 -M x-virtio-msg -m 2G \
        -display none \
        -device virtio-msg-bus-versal,dev=/dev/uio0 \
        -device virtio-net-device,mq=on,netdev=net0,iommu_platform=on \
        -netdev tap,id=net0,ifname=tap0,script=no,downscript=no \
	>qemu.log 2>&1 </dev/null &

# Wait for bridge to come up
sleep 3

# Bring up xenbr0 together with tap0
ifup xenbr0

sleep 10
