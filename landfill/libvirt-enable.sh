#!/bin/bash

pacman -S --needed \
  libvirt \
  qemu-base \
  qemu-tools \
  qemu-system-x86 \
  qemu-system-x86-firmware \
  qemu-audio-spice \
  qemu-chardev-spice \
  qemu-hw-display-qxl \
  qemu-hw-display-virtio-gpu \
  qemu-hw-display-virtio-gpu-gl \
  qemu-hw-display-virtio-gpu-pci \
  qemu-hw-display-virtio-gpu-pci-gl \
  qemu-hw-usb-host \
  qemu-ui-egl-headless \
  qemu-ui-spice-core \
  qemu-ui-spice-app \
  # EOL

for drv in qemu interface network nodedev nwfilter secret storage proxy
do
  systemctl unmask virt${drv}d.service
  systemctl unmask virt${drv}d{,-ro,-admin}.socket
  systemctl enable virt${drv}d{,-ro,-admin}.socket
  systemctl start virt${drv}d{,-ro,-admin}.socket
  if [[ $drv == proxy ]]; then
    systemctl enable virt${drv}d.service
    systemctl start virt${drv}d.service
  fi
done
