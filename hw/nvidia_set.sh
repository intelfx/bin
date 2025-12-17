#!/bin/bash

set -eo pipefail
shopt -s lastpipe

. /home/operator/bin/lib/lib.sh

_usage() {
	cat <<EOF
Usage:
	$LIB_ARGV0 [-R|--reset] [-S|--stop]
	$LIB_ARGV0 [-p|--power POWER-LIMIT] [-g|--gpu-clock GPU-OFFSET] [-m|--mem-clock MEM-OFFSET] [-f|--fan FAN-SPEED% | --fa|--fan-auto] [-S|--stop]
EOF
}

systemd_maybe_run() {
	[[ "$1" == --unit ]] || die "systemd_maybe_run: expected --unit UNIT-NAME at the first position"
	local unit="$2"
	shift 2

	case "$(systemctl is-active "$unit")" in
	active)
		return 0 ;;
	inactive)
		;;
	*)
		systemctl reset-failed "$unit"
		;;
	esac

	systemd-run --unit "$unit" "$@"
}

start_xorg() {
	# FIXME -- wait for Xorg startup (how? Xorg does not support any established readiness protocols)
	systemd_maybe_run --unit nvidia-xorg.service \
		/usr/bin/Xorg "$NVIDIA_DISPLAY" -keeptty -novtswitch -config /etc/X11/xorg-nvidia.conf
}

start_fancontrol() {
	systemd_maybe_run --unit nvidia-nvfancontrol.service \
		-p BindsTo=nvidia-xorg.service \
		-p After=nvidia-xorg.service \
		-E DISPLAY="$NVIDIA_DISPLAY" \
		/usr/bin/fancontrol --debug --force --limits 0
}

nvidia_settings() {
	nvidia-settings -c "$NVIDIA_DISPLAY" "$@" |& grep -vE '^$|libEGL warning' >&2
}

nvidia_set_clock() {
	local name="$1" attr="$2" clock="$3"
	local cmd
	if [[ $clock =~ (.*)/(.*) ]]; then
		local perf="${BASH_REMATCH[1]}"
		clock="${BASH_REMATCH[2]}"
		log "Setting $name clock offset [perf=$perf]: $clock MHz"
		cmd="[gpu:0]/$attr[$perf]=$clock"
	else
		log "Setting $name clock offset [all]: $clock MHz"
		cmd="[gpu:0]/$attr=$clock"
	fi
	nvidia_settings -a "$cmd"
}

NVIDIA_DISPLAY=:99
POWER_MAX=350  # FIXME -- hardcoded for RTX3090
ARG_RESET=
ARG_STOP=
ARG_POWER=
ARG_GPU_CLOCK=
ARG_MEM_CLOCK=
ARG_FAN_PCT=
ARG_FAN_AUTO=
ARG_FAN_CONTROL=
declare -A ARGS=(
	[-R|--reset]="ARG_RESET"
	[-S|--stop]="ARG_STOP"
	[-p|--power:]="ARG_POWER"
	[-g|--gpu-clock:]="ARG_GPU_CLOCK"
	[-m|--mem-clock:]="ARG_MEM_CLOCK"
	[-f|--fan:]="ARG_FAN_PCT"
	[--fa|--fan-auto]="ARG_FAN_AUTO"
)
parse_args ARGS "$@" || usage

if [[ $ARG_RESET ]]; then
	if [[ $ARG_POWER || $ARG_GPU_CLOCK || $ARG_MEM_CLOCK || $ARG_FAN_PCT || $ARG_FAN_AUTO ]]; then
		err "-R/--reset must not be used with any other GPU settings"
		usage
	fi
	ARG_POWER="$ARG_POWER_MAX"
	ARG_GPU_CLOCK=0
	ARG_MEM_CLOCK=0
	ARG_FAN_AUTO=1
fi

if [[ $ARG_POWER || $ARG_GPU_CLOCK || $ARG_MEM_CLOCK || $ARG_FAN_PCT || $ARG_FAN_AUTO ]]; then
	start_xorg
fi

if [[ $ARG_FAN_PCT ]]; then
	log "Setting fixed fan speed: $ARG_FAN_PCT%"
	nvidia_settings -a "[gpu:0]/GPUFanControlState=1"
	nvidia_settings -a "[fan:0]/GPUTargetFanSpeed=$ARG_FAN_PCT"
elif [[ $ARG_FAN_AUTO ]]; then
	log "Enabling automatic fan control"
	nvidia_settings -a "[gpu:0]/GPUFanControlState=0"
fi

if [[ $ARG_POWER ]]; then
	log "Setting power limit: $ARG_POWER W"
	nvidia-smi -pl "$ARG_POWER"
fi

if [[ $ARG_GPU_CLOCK ]]; then
	nvidia_set_clock "GPU" "GPUGraphicsClockOffset" "$ARG_GPU_CLOCK"
fi

if [[ $ARG_MEM_CLOCK ]]; then
	nvidia_set_clock "MEM" "GPUMemoryTransferRateOffset" "$ARG_MEM_CLOCK"
fi

if [[ $ARG_STOP ]]; then
	systemctl stop nvidia-xorg.service
fi
