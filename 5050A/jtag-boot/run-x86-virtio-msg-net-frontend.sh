#!/bin/sh

set -x

sudo insmod virtio_msg_transport.ko
sudo insmod virtio_msg_amp.ko
sudo insmod virtio_msg_sapphire.ko

sudo dmesg | tail -n 25

sudo ifconfig enp1s0 up
sudo ifconfig enp1s0 192.168.17.2

ping -c 3 192.168.17.1


