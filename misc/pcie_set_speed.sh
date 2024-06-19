#!/bin/bash

set -eo pipefail
shopt -s lastpipe

. lib.sh || exit

#
# Original algorithm:
# http://alexforencich.com/wiki/en/pcie/set-speed
# "Except where otherwise noted, content on this wiki is licensed under the following license: CC Attribution-Share Alike 4.0 International"
#

_usage() {
    cat <<EOF
Usage: $0 PCIE-DEVICE [PCIE-GEN]
       $0 -l|--list
       $0 -g|--get          PCIE-DEVICE... | [-a|--all]
       $0 -s|--set=PCIE-GEN PCIE-DEVICE...
EOF
}

declare -A _args=(
    [-q|--quiet]="ARG_QUIET"
    [-a|--all]="ARG_ALL"
    [-l|--list]="ARG_MODE_LIST"
    [-g|--get]="ARG_MODE_GET"
    [-s|--set:]="ARG_MODE_SET"
    [--]="ARGS"
)

parse_args _args "$@" || usage

if ! [[ ${ARG_QUIET+set} ]]; then
    export LIBSH_DEBUG=1
    exec 3>&2
else
    exec 3>/dev/null
fi

unset SILENT_SKIP
if [[ ${ARG_ALL+set} ]]; then
    SILENT_SKIP=1
fi


#
# functions
#

listpci() {
    command lspci -n | awk '{ print $1 }'
}

setpci() {
    command setpci "$@" 2>&3
}

pcie_validate_speed() {
    local speed="$1"

    if ! (( speed > 0 && speed < 10 )); then
	die "invalid target speed ${speed@Q}"
    fi

    printf "%d" "$speed"
}

pcie_validate() {
    local odev="$1" dev="$1"

    if ! [[ "$dev" ]]; then
	die "empty device"
    fi

    if ! [[ -e "/sys/bus/pci/devices/$dev" ]]; then
	dev="0000:$dev"
    fi

    if ! [[ -e "/sys/bus/pci/devices/$dev" ]]; then
	die "device ${odev@Q} not found"
    fi

    printf "%s" "$dev"
}

pcie_to_port() {
    local dev="$1"

    dbg "Resolving $dev..."

    local pciec pt
    pciec="$(setpci -s "$dev" CAP_EXP+02.W)" || return
    pt="$((("0x$pciec" & 0xF0) >> 4))"

    case "$pt" in
    0|1|5) printf "%s" "$(extract 2 "$(readlink "/sys/bus/pci/devices/$dev")")" ;;
    *) printf "%s" "$dev" ;;
    esac
}

if_not_silent() {
    if ! [[ ${SILENT_SKIP+set} ]]; then
	"$@"
    fi
}

get_bw() {
    local arg="$1" text
    case "$arg" in
    '') text='-' ;;
    1) text='2.5GT/s' ;;
    2) text='5GT/s' ;;
    3) text='8GT/s' ;;
    4) text='16GT/s' ;;
    5) text='32GT/s' ;;
    *) die "do not know anything about PCIe Gen $arg, are you high?" ;;
    esac

    printf "%s" "$text"
}

get_bridge() {
    local odev="$1" dev="$2"
    if [[ "$odev" == "$dev" ]]; then
	dev="-"
    fi
    printf "%s" "$dev"
}

print_get_row() {
    if [[ ${ARG_QUIET+set} ]]; then
	printf >&2 "%15s %15s %7s %7s %7s  %s\n" "${@:1:6}"
    fi
}

print_get_header() {
    print_get_row DEVICE BRIDGE ACT TGT MAX COMMENT
}

print_get() {
    print_get_row "$odev" "$(get_bridge "$odev" "$dev")" \
	"$(get_bw "$act_speed")" \
	"$(get_bw "$tgt_speed")" \
	"$(get_bw "$max_speed")" \
	"$1"
}


pcie_get_speed() {
    local odev="$1" dev
    local LIBSH_LOG_PREFIX="$odev"

    odev="$(pcie_validate "$odev")"
    dev="$(pcie_to_port "$odev")" || { if_not_silent print_get 'no port'; return 0; }
    dev="$(pcie_validate "$dev")" || { if_not_silent print_get 'bad port'; return 0; }

    if [[ "$odev" != "$dev" ]]; then
	dbg "Querying $odev -> $dev..."
    else
	dbg "Querying $dev..."
    fi

    local lnkcap lnksta lnkctl2
    local max_speed act_speed tgt_speed

    lnkcap="$(setpci -s "$dev" CAP_EXP+0c.L)" || { print_get 'failed to get LnkSta'; return 1; }
    max_speed="$(("0x$lnkcap" & 0xF))"

    dbg "LnkCap: $lnkcap"
    dbg "Max link speed: $max_speed"

    lnksta="$(setpci -s "$dev" CAP_EXP+12.W)" || { print_get 'failed to get LnkSta'; return 1; }
    act_speed="$(("0x$lnksta" & 0xF))"

    dbg "LnkSta: $lnksta"
    dbg "Cur link speed: $act_speed"

    lnkctl2="$(setpci -s "$dev" CAP_EXP+30.L)" || { print_get 'failed to get LnkCtl2'; return 1; }
    tgt_speed="$(("0x$lnkctl2" & 0xF))"

    dbg "LnkCtl2: $lnkctl2"
    dbg "Tgt link speed: $tgt_speed"

    print_get
}

print_set_row() {
    if [[ ${ARG_QUIET+set} ]]; then
	printf >&2 "%15s %15s %7s %7s %7s %7s %7s  %s\n" "${@:1:8}"
    fi
}

print_set_header() {
    print_set_row DEVICE BRIDGE P.ACT P.TGT ACT TGT MAX COMMENT
}

print_set() {
    print_set_row "$odev" "$(get_bridge "$odev" "$dev")" \
	"$(get_bw "$act_speed")" \
	"$(get_bw "$tgt_speed")" \
	"$(get_bw "$new_speed")" \
	"$(get_bw "$des_speed")" \
	"$(get_bw "$max_speed")" \
	"$1"
}

pcie_set_speed() {
    local LIBSH_LOG_PREFIX="$odev"
    local odev="$1" speed="$2" dev

    speed="$(pcie_validate_speed "$speed")"
    odev="$(pcie_validate "$odev")"
    dev="$(pcie_to_port "$odev")" || { if_not_silent print_set 'no port'; return 0; }
    dev="$(pcie_validate "$dev")" || { if_not_silent print_set 'bad port'; return 0; }

    if [[ "$odev" != "$dev" ]]; then
	dbg "Configuring $odev -> $dev..."
    else
	dbg "Configuring $dev..."
    fi

    local lnkcap lnksta lnkctl lnkctl2 
    local lnkctl2_new lnkctl_new
    local max_speed act_speed tgt_speed des_speed new_speed

    lnkcap="$(setpci -s "$dev" CAP_EXP+0c.L)" || { print_set 'failed to get LnkCap'; return 1; }
    max_speed="$(("0x$lnkcap" & 0xF))"

    dbg "LnkCap: $lnkcap"
    dbg "Max link speed: $max_speed"

    if (( speed > max_speed )); then
	warn "Target ($speed) > capability ($max_speed), limiting"
	speed="$max_speed"
    fi

    lnksta="$(setpci -s "$dev" CAP_EXP+12.W)" || { print_set 'failed to get LnkSta'; return 1; }
    act_speed="$(("0x$lnksta" & 0xF))"

    dbg "LnkSta: $lnksta"
    dbg "Current link speed: $act_speed"

    lnkctl2="$(setpci -s "$dev" CAP_EXP+30.L)" || { print_set 'failed to get LnkCtl2'; return 1; }
    tgt_speed="$(("0x$lnkctl2" & 0xF))"

    dbg "Initial LnkCtl2: $lnkctl2"
    dbg "Initial target link speed: $tgt_speed"

    des_speed="$speed"
    lnkctl2_new="$(printf "%08x" "$((("0x$lnkctl2" & 0xFFFFFFF0) | des_speed))")"

    dbg "Updated target link speed: $speed"
    dbg "Updated LnkCtl2: $lnkctl2_new"

    setpci -s "$dev" CAP_EXP+30.L="$lnkctl2_new" || { print_set 'failed to set LnkCtl2'; return 1; }

    dbg "Triggering link retraining..."

    lnkctl="$(setpci -s "$dev" CAP_EXP+10.L)" || { print_set 'failed to get LnkCtl'; return 1; }

    dbg "Initial LnkCtl: $lnkctl"

    lnkctl_new="$(printf "%08x" "$(("0x$lnkctl" | 0x20))")"

    dbg "Updated LnkCtl: $lnkctl_new"

    setpci -s "$dev" CAP_EXP+10.L="$lnkctl_new" || { print_set 'failed to set LnkCtl'; return 1; }

    sleep 0.1

    lnksta="$(setpci -s "$dev" CAP_EXP+12.W)" || { print_set 'failed to get LnkSta'; return 1; }
    new_speed=$(("0x$lnksta" & 0xF))

    dbg "LnkSta: $lnksta"
    dbg "New link speed: $new_speed"
    print_set
}


#
# main
#

maybe_allpci() {
    if [[ ${ARG_ALL+set} ]]; then
	if (( ${#ARGS[@]} )); then
	    usage "invalid number of positional arguments (none expected with \`--all\`)"
	fi
	listpci | readarray -t ARGS
    fi
}

mode=0
if [[ ${ARG_MODE_GET+set} ]]; then (( ++mode )); fi
if [[ ${ARG_MODE_SET+set} ]]; then (( ++mode )); fi
if [[ ${ARG_MODE_LIST+set} ]]; then (( ++mode )); fi

if (( mode > 1 )); then
    usage "--get, --set and --list are mutually exclusive"
elif [[ ${ARG_MODE_LIST+set} ]]; then
    if (( ${#ARGS[@]} )); then
	usage "invalid number of positional arguments (none expected with \`--list\`)"
    fi
    listpci
elif [[ ${ARG_MODE_GET+set} ]]; then
    maybe_allpci

    if (( ${#ARGS[@]} )); then
	print_get_header
	for arg in "${ARGS[@]}"; do
	    pcie_get_speed "$arg"
	done
    fi | sponge
elif [[ ${ARG_MODE_SET+set} ]]; then
    #maybe_allpci
    if [[ ${ARG_ALL+set} ]]; then
	die "not doing that"
    fi

    if (( ${#ARGS[@]} )); then
	print_set_header
	for arg in "${ARGS[@]}"; do
	    pcie_set_speed "$arg" "$ARG_MODE_SET"
	done
    fi | sponge
elif (( ${#ARGS[@]} == 2 )); then
    print_set_header
    pcie_set_speed "${ARGS[0]}" "${ARGS[1]}"
elif (( ${#ARGS[@]} == 1 )); then
    print_get_header
    pcie_get_speed "${ARGS[0]}"
else
    usage "unexpected number of positional arguments (1 or 2 expected)"
fi
