#!/bin/bash
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
