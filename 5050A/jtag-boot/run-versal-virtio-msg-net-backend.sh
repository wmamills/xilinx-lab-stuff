#!/bin/sh

set -x

qemu-system-aarch64 -M x-virtio-msg -m 2G \
        -serial mon:stdio -display none \
        -device virtio-msg-bus-versal,dev=/dev/uio0 \
        -device virtio-net-device,mq=on,netdev=net0,iommu_platform=on \
        -netdev tap,id=net0,ifname=tap0,script=no,downscript=no

# Wait for bridge to come up
#sleep 3

# Bring up xenbr0 together with tap0
#ifup xenbr0
