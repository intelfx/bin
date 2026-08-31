#!/bin/bash

#!/bin/bash

set -eo pipefail
shopt -s lastpipe
. lib.sh

_usage() {
  cat <<EOF
Usage: $0 [ARGS...]
EOF
}

trace() {
  local -
  set -x
  "$@"
}


#
# args
#

declare -A _args=(
  [-h|--help]=ARG_USAGE
  [--virtio]=ARG_VIRTIO
  [--code:]=ARG_OVMF_CODE
  [--vars:]=ARG_OVMF_VARS
  [--vars-reset]=ARG_RESET_VARS
  [--]=ARGS
)
parse_args _args "$@" || usage
[[ ! $ARG_USAGE ]] || usage

ORIG_OVMF_CODE=/usr/share/edk2/x64/OVMF_CODE.4m.fd
ORIG_OVMF_VARS=/usr/share/edk2/x64/OVMF_VARS.4m.fd
LOCAL_OVMF_VARS="$PWD/scratch_VARS.fd"


#
# main
#

QEMU_ARGS=(
  qemu-system-x86_64
  -name scratch
  -machine q35,accel=kvm,smm=on
  -cpu host
  -m 1024
  -drive if=pflash,format=raw,readonly=on,file="${ARG_OVMF_CODE-"$ORIG_OVMF_CODE"}"
  -drive if=pflash,format=raw,file="$LOCAL_OVMF_VARS"
  -cdrom ~/tmp/big/dist/local/archlinux-my-cain-latest-x86_64.iso
  -vga std
  -display gtk
  -boot menu=on,splash-time=3000,strict=on
)


if [[ $ARG_VIRTIO ]]; then
  QEMU_ARGS+=(
    -device virtio-keyboard-pci,bus=pcie.0
  )
fi

if [[ $ARG_RESET_VARS || ! -e $LOCAL_OVMF_VARS ]]; then
  log "Resetting vars:"
  trace cp -a "${ARG_OVMF_VARS-"$ORIG_OVMF_VARS"}" "$LOCAL_OVMF_VARS"
fi

log "Running QEMU:"
trace "${QEMU_ARGS[@]}" "${ARGS[@]}"

log "Dumping vars:"
trace virt-fw-vars --input "$LOCAL_OVMF_VARS" --print --verbose | grep -E 'Con(In|Out)' -A2
