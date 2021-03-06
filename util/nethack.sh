#!/bin/bash

set -e
. lib.sh || exit

NH_LIVE_DIR="/var/games/nethack"
NH_SAVE_DIR="$(systemd-path user-shared)/nethack"
NH_LAST_SAVE=""
NH_LAST_LOAD=""

nh_echo() {
	echo "$@" >&2
}

nh_save_name() {
	local name date description
	name="$(date "+%Y-%m-%d %H:%M:%S")"
	read -p "Enter description: " description
	if [[ $description ]]; then
		name="$name ($description)"
	fi
	echo "$name"
}

nh_save_list() {
	find "$NH_SAVE_DIR" -mindepth 2 -maxdepth 2 -type f -name ".nethack-save" -printf '%P\n' | sed -r 's|/[^/]+$||'
}

nh_save_files_in() {
	find "$1" -type f -name "$UID*"
}

nh_del_save() {
	local save_name="$1"
	local save_dir="$NH_SAVE_DIR/$save_name"
	nh_echo "Removing save '$save_name'..."
	if ! [[ -e "$save_dir" ]]; then
		die "Save directory '$save_dir' does not exist!"
	fi
	rm -r "$save_dir"
}

nh_can_save() {
	declare -a save_files
	readarray -t save_files < <(nh_save_files_in "$NH_LIVE_DIR/save")
	if (( ${#save_files[@]} )); then
		return 0
	else
		return 1
	fi
}

nh_save() {
	declare -a save_files
	readarray -t save_files < <(nh_save_files_in "$NH_LIVE_DIR/save")
	if (( ${#save_files[@]} )); then
		if (( ${#save_files[@]} != 1 )); then
			die "Found ${#save_files[@]} != 1 live save files for uid $UID!"
		fi

		local save_name="$(nh_save_name)"
		local save_dir="$NH_SAVE_DIR/$save_name"
		nh_echo "Saving as '$save_name'..."
		if [[ -e "$save_dir" ]]; then
			die "Attempting to save an already existing save: '$save_name'"
		fi

		mkdir -p "$save_dir"
		mv "${save_files[@]}" -t "$save_dir/"
		touch "$save_dir/.nethack-save"
		NH_LAST_SAVE="$save_name"
	else
		nh_echo "Nothing to save!"
		return 1
	fi
}

nh_can_load() {
	declare -a save_names
	readarray -t save_names < <(nh_save_list)

	if (( ${#save_names[@]} )); then
		return 0
	else
		return 1
	fi
}

nh_load() {
	local s="$1"
	declare -a save_names
	readarray -t save_names < <(nh_save_list)

	if [[ "$s" ]]; then
		if ! [[ -d "$NH_SAVE_DIR/$s" ]]; then
			die "Attempting to load a bad save: '$s'"
		fi
	fi

	NH_LAST_LOAD=""
	if (( ${#save_names[@]} )); then
		if ! [[ "$s" ]]; then
			nh_echo "Choose a save to load:"
			select s in "${save_names[@]}"; do
				if [[ -d "$NH_SAVE_DIR/$s" ]]; then
					break
				fi
				nh_echo "Bad choice: '$s'"
			done
		fi
		nh_echo "Loading '$s'..."

		declare -a save_files
		readarray -t save_files < <(nh_save_files_in "$NH_SAVE_DIR/$s")
		if (( ${#save_files[@]} != 1 )); then
			die "Found ${#save_files[@]} != 1 save files in save $s!"
		fi
		if (( NH_WIZARD )); then
			cp -v "${save_files[0]}" "$NH_LIVE_DIR/save/${UID}wizard.${save_files[0]##*.}"
		else
			cp "${save_files[@]}" -t "$NH_LIVE_DIR/save/"
		fi
		NH_LAST_LOAD="$s"
	else
		nh_echo "Nothing to load!" >&2
		return 1
	fi
}

ask() {
	local query="$1"
	local default="$(<<<"$2" tr -d '[a-z]' | tr '[A-Z]' '[a-z]')"
	local answers="$(<<<"$2" tr '[A-Z]' '[a-z]')"
	local r
	while :; do
		nh_echo -n "$1 "
		read r; r="$(<<<"$r" tr '[A-Z]' '[a-z]')"
		case "$r" in
		[$answers])
			echo "$r"; return 0 ;;
		"")
			echo "$default"; return 0 ;;
		*)
			;;
		esac
	done
}

nh_run() {
	while :; do
		NH_PREV_LOAD="$NH_LAST_LOAD"
		NH_LAST_LOAD=""
		if [[ $NH_LAST_SAVE ]]; then
			nh_echo "Reloading the just saved game..."
			nh_load "$NH_LAST_SAVE"
		elif ! [[ $NH_LAST_SAVE ]] && [[ $NH_PREV_LOAD ]]; then
			ans="$(ask "Reload last (l) or load another game (y)? [L/y/n/q]" "Lynq")"
			case "$ans" in
			l) nh_load "$NH_PREV_LOAD" ;;
			y) nh_load ;;
			q) exit 0 ;;
			esac
		elif nh_can_load; then
			ans="$(ask "Load a game? [Y/n/q]" "Ynq")"
			case "$ans" in
			y) nh_load ;;
			q) exit 0 ;;
			esac
		elif [[ $NH_LOOPED ]]; then
			ans="$(ask "Start another game? [Y/q]" "Yq")"
			case "$ans" in
			y) ;;
			q) exit 0 ;;
			esac
		fi

		if ! [[ $NH_LAST_LOAD ]]; then
			nh_echo "Starting a new game..."
		fi

		/usr/bin/nethack "${nh_args[@]}"

		NH_LOOPED=1
		NH_LAST_SAVE=""
		if nh_can_save; then
			nh_save
			if [[ $NH_LAST_LOAD ]]; then
				ans="$(ask "Remove previous loaded save '$NH_LAST_LOAD'? [Y/n]" "Yn")"
				case "$ans" in
				y) nh_del_save "$NH_LAST_LOAD" ;;
				esac
			fi
		fi
	done
}


op="$1"
shift
nh_args=( "$@" )
for a in "${nh_args[@]}"; do
	case "$a" in
	-D) NH_WIZARD=1 ;;
	esac
done

case "$op" in
save)
	nh_save
	;;
load)
	nh_load
	;;
run)
	nh_run
	;;
*)
	die "Bad operation: '$op'"
	;;
esac
