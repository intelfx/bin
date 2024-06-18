#!/bin/bash

set -eo pipefail
shopt -s lastpipe

. lib.sh || exit

#
# http://alexforencich.com/wiki/en/pcie/set-speed
# "Except where otherwise noted, content on this wiki is licensed under the following license: CC Attribution-Share Alike 4.0 International"
#

_usage() {
    cat <<EOF
Usage: $0 PCIE-DEVICE [PCIE-GEN]
EOF
}

case "$#" in
2) dev="$1"; speed="$2" ;;
1) dev="$1"; unset speed ;;
*) usage "expected 1 or 2 positional parameters" ;;
esac

if ! [[ "$dev" ]]; then
    die "empty device"
fi

if ! [[ -e "/sys/bus/pci/devices/$dev" ]]; then
    dev="0000:$dev"
fi

if ! [[ -e "/sys/bus/pci/devices/$dev" ]]; then
    die "device ${dev@Q} not found"
fi

log "Resolving $dev..."

pciec="$(setpci -s "$dev" CAP_EXP+02.W)"
pt="$((("0x$pciec" & 0xF0) >> 4))"

port="$(extract 2 "$(readlink "/sys/bus/pci/devices/$dev")")"

case "$pt" in
0|1|5) dev="$port" ;;
esac

if [[ ${speed+set} ]]; then
    log "Configuring $dev..."
else
    log "Querying $dev..."
fi

lnkcap="$(setpci -s "$dev" CAP_EXP+0c.L)"
lnksta="$(setpci -s "$dev" CAP_EXP+12.W)"

max_speed="$(("0x$lnkcap" & 0xF))"
act_speed="$(("0x$lnksta" & 0xF))"

log "LnkCap: $lnkcap"
log "Max link speed: $max_speed"
log "LnkSta: $lnksta"
log "Current link speed: $act_speed"

lnkctl2="$(setpci -s "$dev" CAP_EXP+30.L)"

if ! [[ ${speed+set} ]]; then
    log "LnkCtl2: $lnkctl2"
    log "Target link speed: $(("0x$lnkctl2" & 0xF))"
    exit
fi

log "Original LnkCtl2: $lnkctl2"
log "Original target link speed: $(("0x$lnkctl2" & 0xF))"

lnkctl2_new="$(printf "%08x" "$((("0x$lnkctl2" & 0xFFFFFFF0) | speed))")"

log "New target link speed: $speed"
log "New LnkCtl2: $lnkctl2_new"

setpci -s "$dev" CAP_EXP+30.L="$lnkctl2_new"

log "Triggering link retraining..."

lnkctl="$(setpci -s "$dev" CAP_EXP+10.L)"

log "Original LnkCtl: $lnkctl"

new_lnkctl="$(printf "%08x" "$(("0x$lnkctl" | 0x20))")"

log "New LnkCtl: $new_lnkctl"

setpci -s "$dev" CAP_EXP+10.L="$new_lnkctl"

sleep 0.1

lnksta="$(setpci -s "$dev" CAP_EXP+12.W)"
act_speed=$(("0x$lnksta" & 0xF))

log "LnkSta: $lnksta"
log "Current link speed: $act_speed"
