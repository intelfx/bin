#!/bin/bash

. lib.sh || exit

PTS_ROOT="$HOME/.phoronix-test-suite"
PTS_TEST_ROOT="$PTS_ROOT/installed-tests"

escape() {
	if [[ $1 == . ]]; then
		echo "pts"
	else
		echo "pts-$(systemd-escape "$1")"
	fi
}

pts_save_dir() {
	local root="$1" dir="$2"
	local dir_rel file
	local -a dirs

	dir="$(realpath -qm "$dir")"
	local dirdir="$(dirname "$dir")"
	local dirname="$(basename "$dir")"
	trace find "$dirdir" -mindepth 1 -maxdepth 1 -type d -name "$dirname" | readarray -t dirs
	if (( ${#dirs[@]} == 1 )); then
		dir_rel="$(realpath -qe --relative-base="$root" "$dirs")"
		if [[ $dir_rel == /* ]]; then
			die "Attempting to save $dirs not under $root"
		fi

		file="$(systemd-escape "$dir_rel")"
		log "Saving $root/$dir_rel into $root/$file.tar.zst"
		dry_run tar -cf "$root/$file.tar.zst" -I 'zstd -T0 -11' -C "$root" "$dir_rel"
	else
		die "Found ${#dirs[@]} directories matching $dir, cannot proceed"
	fi

	SAVED=1
	SAVED_FILE="$root/$file.tar.zst"
	SAVED_DIR="$dirs"
}

pts_restore_dir() {
	local nofail=0
	while (( $# )); do
		case "$1" in
		--nofail) nofail=1; shift ;;
		*) break ;;
		esac
	done

	local root="$1" dir="$2"
	local dir_rel file
	local -a files

	dir_rel="$(realpath -qe --relative-base="$root" "$dir")"
	if [[ $dir_rel == /* ]]; then
		die "Attempting to restore $dir not under $root"
	fi
	file="$(systemd-escape "$dir_rel")"

	mkdir -p "$root"
	trace find "$root" -mindepth 1 -maxdepth 1 -type f -name "${file//\\/\\\\}.tar*" | readarray -t files
	if (( ${#files[@]} == 1 )); then
		mkdir -p "$dir"
		dry_run find "$dir" -mindepth 1 -maxdepth 1 -execdir rm -rf {} \+
		dry_run tar -xaf "$files" -C "$root"
	elif (( ${#files[@]} == 0 && nofail )); then
		return
	else
		die "Found ${#files[@]} backups of $dir in $root (as $root/$file.tar*), cannot proceed"
	fi

	if ! [[ -d $dir && -s $dir ]]; then
		die "Failed to restore $dir from $files -- directory not in archive"
	fi

	RESTORED=1
	RESTORED_FILE="$files"
	RESTORED_DIR="$dir"
}

pts_restore_file() {
	local nofail=0
	while (( $# )); do
		case "$1" in
		--nofail) nofail=1; shift ;;
		*) break ;;
		esac
	done

	local root="$1" file="$2"
	local dir_rel dir
	local -a files

	mkdir -p "$root"
	trace find "$root" -mindepth 1 -maxdepth 1 -type f -name "${file//\\/\\\\}.tar*" | readarray -t files
	if (( ${#files[@]} == 1 )); then
		file_rel="${files#$root/}"
		dir_rel="$(systemd-escape -u "${file_rel%.tar*}")"
		if [[ $dir_rel == /* ]]; then
			die "Attempting to restore from $files encoding a non-relative path"
		fi
		dir="$root/$dir_rel"

		log "Restoring $dir from $files"
		mkdir -p "$dir"
		dry_run find "$dir" -mindepth 1 -maxdepth 1 -execdir rm -rf {} \+
		dry_run tar -xaf "$files" -C "$root"
	elif (( ${#files[@]} == 0 && nofail )); then
		return
	else
		die "Found ${#files[@]} backups matching $file in $root, cannot proceed"
	fi

	if ! [[ -d $dir && -s $dir ]]; then
		die "Failed to restore $dir from $files -- directory not in archive"
	fi

	RESTORED=1
	RESTORED_FILE="$files"
	RESTORED_DIR="$dir"
}

pts_restore() {
	pts_restore_dir "$HOME" "$PTS_ROOT"
}

pts_save() {
	pts_save_dir "$HOME" "$PTS_ROOT"
}

pts_install() {
	local test="$1" test_full test_file
	local test_subdir test_basename
	local -a test_files test_dirs

	# see if we have saved any matching test
	pts_restore_file --nofail "$PTS_TEST_ROOT" "$(systemd-escape "$test-")*"

	# install anyway, maybe we have a newer version
	phoronix-test-suite install "$test"

	# save whatever was installed
	pts_save_dir "$PTS_TEST_ROOT" "$PTS_TEST_ROOT/$test-*"
}

pts_run() (
	local name="$1"
	shift 1

	local -a env_str options_str
	local k v arg
	for k in "${!PTS_ENV[@]}"; do
		if [[ $k == $name.* ]]; then
			env_str+=("${k#$name.}=${PTS_ENV[$k]}")
		fi
	done
	for arg in "${ARG_PTS_ENV[@]}"; do
		if ! [[ $arg == *=* ]]; then
			die "Malformed --pts-env argument: $arg"
		fi
		env_str+=("$arg")
	done

	for k in "${!PTS_OPTIONS[@]}"; do
		if [[ $k == $name.* ]]; then
			options_str+=("${k}=${PTS_OPTIONS[$k]}")
		fi
	done
	for arg in "${ARG_PTS_OPTIONS[@]}"; do
		if ! [[ $arg == *=* ]]; then
			die "Malformed --pts-option argument: $k"
		fi
		k="${arg%%=*}"
		v="${arg#*=}"

		if [[ $k == $name.* ]]; then
			:
		elif [[ $k == *.* ]]; then
			die "--pts-option argument starts with wrong test name: $arg"
		else
			warn "--pts-option argument does not start with test name, fixing: [$name.]$arg"
			arg="$name.$arg"
		fi
		options_str+=("$arg")
	done

	if (( ${#env_str[@]} )); then
		log "Setting PTS environment variables:"
		for arg in "${env_str[@]}"; do
			log " - $arg"
		done
	fi
	if (( ${#options_str[@]} )); then
		log "Setting PTS test options (\$PRESET_OPTIONS):"
		for arg in "${options_str[@]}"; do
			log " - $arg"
		done
	fi

	for arg in "${env_str[@]}"; do
		export "$arg"
	done
	export PRESET_OPTIONS="$(join ';' "${options_str[@]}")"

	phoronix-test-suite benchmark "$name" "$@"
)



#
# constants
#

declare -A PTS_OPTIONS=(
	[pts/pgbench.scaling-factor]=100
	[pts/pgbench.clients]=800
	[pts/pgbench.run-mode]="Read Write"
)

declare -A PTS_ENV=(
	[pts/pgbench.FORCE_TIMES_TO_RUN]=10
	[pts/pgbench.TEST_RESULTS_NAME]=fstests
)

#
# args
#

declare -A ARGS=(
	[--part:]=ARG_PART
	[--fs:]=ARG_FSTYPE
	[--mkfs:]=ARG_MKFS_OPTIONS
	[--mount:]=ARG_MOUNT_OPTIONS
	[--cmd:]="ARG_CMD append"
	[--pts-env:]="ARG_PTS_ENV append"
	[--pts-option:]="ARG_PTS_OPTIONS append"
	[--install-only]=ARG_INSTALL_ONLY
	[--]=ARGS_REMAINDER
)

parse_args ARGS "$@" || usage
(( ${#ARGS_REMAINDER[@]} > 0 )) || usage

ARG_TEST="${ARGS_REMAINDER[0]}"

#
# mount scratch on pts dir
#

mkdir -p "$PTS_ROOT"
if [[ ${ARG_PART+set} ]]; then
	[[ ${ARG_FSTYPE+set} ]] || die "--part set without --fstype"
	if mountpoint -q "$PTS_ROOT"; then
		dry_run sudo umount "$PTS_ROOT"
	fi
	dry_run sudo blkdiscard -f "$ARG_PART"
	dry_run sudo mkfs -t "$ARG_FSTYPE" ${ARG_MKFS_OPTIONS+$ARG_MKFS_OPTIONS} "$ARG_PART"
	dry_run sudo mount -t "$ARG_FSTYPE" "$ARG_PART" ${ARG_MOUNT_OPTIONS+-o "$ARG_MOUNT_OPTIONS"} "$PTS_ROOT"
	dry_run sudo chown "$(id -u):$(id -g)" "$PTS_ROOT"
	dry_run sudo rm -df "$PTS_ROOT/lost+found"
	log "Re-initialized and mounted $ARG_PART (as $ARG_FSTYPE) on $PTS_ROOT"
else
	[[ ! ${ARG_FSTYPE+set} ]] || die "--fstype set without --part"
	[[ ! ${ARG_MKFS_OPTIONS+set} ]] || die "--mkfs set without --part"
	[[ ! ${ARG_MOUNT_OPTIONS+set} ]] || die "--mount set without --part"
	dry_run sudo find "$PTS_ROOT" -mindepth 1 -maxdepth 1 -execdir rm -rf {} \+
	log "Cleared $PTS_ROOT"
fi

#
# restore pts dir
#

pts_restore
pts_install "$ARG_TEST"
pts_save
if ! [[ ${ARG_INSTALL_ONLY+set} ]]; then
	pts_run "$ARG_TEST"
	pts_restore_file "$PTS_TEST_ROOT" "$SAVED_FILE"  # drop modified test state
	pts_save
fi
