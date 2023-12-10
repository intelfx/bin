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
	local dirdir dirname
	local dir_rel file
	local -a dirs

	dir="$(cd "$root"; realpath -qm "$dir")"
	dirdir="$(dirname "$dir")"
	dirname="$(basename "$dir")"

	mkdir -p "$dirdir"
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
	SAVED_DIR="$root/$dir_rel"
}

pts_clear_dir() {
	local root="$1" dir="$2"
	local dirdir dirname
	local dir_rel file
	local -a dirs
	local d

	dir="$(cd "$root"; realpath -qm "$dir")"
	dirdir="$(dirname "$dir")"
	dirname="$(basename "$dir")"

	mkdir -p "$dirdir"
	trace find "$dirdir" -mindepth 1 -maxdepth 1 -type d -name "$dirname" | readarray -t dirs
	for d in "${dirs[@]}"; do
		dir_rel="$(realpath -qe --relative-base="$root" "$d")"
		if [[ $dir_rel == /* ]]; then
			die "Attempting to clear $d not under $root"
		fi

		log "Clearing $root/$dir_rel"
		dry_run rm -rf "$root/$dir_rel"
	done
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

	mkdir -p "$root"
	dir_rel="$(cd "$root"; realpath -qm --relative-base="$root" "$dir")"
	if [[ $dir_rel == /* ]]; then
		die "Attempting to restore $dir not under $root"
	fi
	file="$(systemd-escape "$dir_rel")"

	trace find "$root" -mindepth 1 -maxdepth 1 -type f -name "${file//\\/\\\\}.tar*" | readarray -t files
	if (( ${#files[@]} == 1 )); then
		log "Restoring $dir from $files"
		dry_run rm -rf "$dir" || true
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
	local filedir filename
	local dir_rel dir
	local -a files

	mkdir -p "$root"
	file="$(cd "$root"; realpath -qm "$file")"
	filedir="$(dirname "$file")"
	filename="$(basename "$file")"

	mkdir -p "$filedir"
	trace find "$filedir" -mindepth 1 -maxdepth 1 -type f \( -name "${filename//\\/\\\\}" -and -name '*.tar*' \) | readarray -t files
	if (( ${#files[@]} == 1 )); then
		file_rel="${files#$root/}"
		dir_rel="$(systemd-escape -u "${file_rel%.tar*}")"
		if [[ $dir_rel == /* ]]; then
			die "Attempting to restore from $files encoding a non-relative path"
		fi
		dir="$root/$dir_rel"

		log "Restoring $dir from $files"
		dry_run rm -rf "$dir" || true
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
	pts_restore_dir --nofail "$HOME" "$PTS_ROOT"
	ltrap pts_save
}

pts_save() {
	pts_save_dir "$HOME" "$PTS_ROOT"
}

pts_install() {
	local install_only=0
	while (( $# )); do
		case "$1" in
		--install-only) install_only=1; shift ;;
		*) break ;;
		esac
	done

	local test="$1" test_full test_file
	local test_subdir test_basename
	local -a test_files test_dirs

	if ! [[ ${ARG_FORCE_INSTALL+set} ]]; then
		# see if we have saved any matching test
		pts_restore_file --nofail "$PTS_TEST_ROOT" "$(systemd-escape "$test-")*"
	else
		pts_clear_dir "$PTS_TEST_ROOT" "$test-*"
	fi

	# install anyway, maybe we have a newer version
	phoronix-test-suite install "$test"

	# save whatever was installed
	pts_save_dir "$PTS_TEST_ROOT" "$test-*"

	if ! (( install_only )); then
		# remember to reset the test state at the end of the run
		ltrap "pts_restore_file '$PTS_TEST_ROOT' '$SAVED_FILE'"

		# sync disks before running this test
		sync
	fi
}

pts_run() (
	local name="$1"
	shift 1

	local -a env_str options_str
	local -A env_map options_map
	local k v arg

	# load environment variables
	for k in "${!PTS_ENV[@]}"; do
		if [[ $k == $name.* ]]; then
			# test-specific environment variables
			env_map[${k#$name.}]="${PTS_ENV[$k]}"
		elif [[ $k != *.* ]]; then
			# global environment variables
			env_map[$k]="${PTS_ENV[$k]}"
		fi
	done
	for arg in "${ARG_PTS_ENV[@]}"; do
		if ! [[ $arg == *=* ]]; then
			die "Malformed --pts-env argument: $arg"
		fi
		k="${arg%%=*}"
		v="${arg#*=}"

		env_map[$k]="$v"
	done
	if [[ ${ARG_PTS_FILE+set} ]]; then
		env_map[TEST_RESULTS_NAME]="$ARG_PTS_FILE"
	fi
	if [[ ${ARG_PTS_NAME+set} ]]; then
		env_map[TEST_RESULTS_IDENTIFIER]="$ARG_PTS_NAME"
	fi

	# emit environment variables as a K=V array
	for k in "${!env_map[@]}"; do
		env_str+=( "$k=${env_map[$k]}" )
	done

	# load test options
	for k in "${!PTS_OPTIONS[@]}"; do
		if [[ $k == $name.* ]]; then
			options_map[$k]="${PTS_OPTIONS[$k]}"
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
			k="$name.$k"
		fi
		options_map[$k]="$v"
	done

	# emit test options as a K=V array
	for k in "${!options_map[@]}"; do
		options_str+=( "$k=${options_map[$k]}" )
	done

	# log environment variables and test options
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

	# set environment
	for arg in "${env_str[@]}"; do
		export "$arg"
	done
	export PRESET_OPTIONS="$(join ';' "${options_str[@]}")"

	phoronix-test-suite benchmark "$name" "$@"
)

pts_setup_part() {
	mkdir -p "$PTS_ROOT"
	pts_release_part
	ltrap pts_release_part
	if [[ ${ARG_PART+set} ]]; then
		[[ ${ARG_FSTYPE+set} ]] || die "--part set without --fstype"
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
}

pts_release_part() {
	if mountpoint -q "$PTS_ROOT"; then
		log "Unmounting $PTS_ROOT"
		dry_run sudo umount "$PTS_ROOT"
	fi
}


#
# constants
#

declare -A PTS_OPTIONS=(
	[pts/pgbench.scaling-factor]=100
	[pts/pgbench.clients]=800
	[pts/pgbench.run-mode]="Read Write"
)

declare -A PTS_ENV=(
	[TEST_RESULTS_DESCRIPTION]=keep  # XXX needs a patch to p-t-s
	[IGNORE_RUNS]=1
	#[pts/pgbench.FORCE_TIMES_TO_RUN]=10
	[pts/pgbench.TEST_RESULTS_NAME]=fstests
)


#
# args
#

_usage() {
	cat <<"EOF"
Usage: pts-run.sh [--part PARTITION --fs FILESYSTEM [--mkfs MKFS-ARGS] [--mount MOUNT-OPTIONS]]
                  [--pts-env KEY=VALUE ...] [--pts-option KEY=VALUE ...]
                  benchmark TEST | install TEST | PTS-VERB ...

Options:
	--part PARTITION	Mount PARTITION at the phoronix-test-suite
				data directory prior to running the test
	--fs FILESYSTEM		Create FILESYSTEM on PARTITION
				(if PARTITION is specified, FILESYSTEM must
				 also be specified)
	--mkfs MKFS-ARGS	Append MKFS-ARGS to the mkfs cmdline
				(argument will be split at whitespace)
	--mount MOUNT-OPTIONS	Append `-o MOUNT-OPTIONS` to the mount cmdline
				(argument will not be split at whitespace)
	--pts-env KEY=VALUE	Set environment variable KEY to VALUE
				for the phoronix-test-suite process
				(this option may be repeated)
	--pts-option KEY=VALUE	Set test preset option KEY to VALUE
				for the phoronix-test-suite process
				(this will be passed as $PRESET_OPTIONS)
				(this option may be repeated)

Verbs:
	benchmark TEST		Invoke `phoronix-test-suite install TEST`, then
				`phoronix-test-suite benchmark TEST`
	install TEST		Invoke `phoronix-test-suite install TEST`
				(partition setup will be ignored)
	PTS-VERB ...		Invoke `phoronix-test-suite PTS-VERB ...`
				(partition setup will be ignored)
EOF
}

declare -A ARGS=(
	[--part:]=ARG_PART
	[--fs:]=ARG_FSTYPE
	[--mkfs:]=ARG_MKFS_OPTIONS
	[--mount:]=ARG_MOUNT_OPTIONS
	[--pts-env:]="ARG_PTS_ENV append"
	[--pts-option:]="ARG_PTS_OPTIONS append"
	[--pts-test-file:]="ARG_PTS_FILE"
	[--pts-test-name:]="ARG_PTS_NAME"
	[--force-install]="ARG_FORCE_INSTALL"
	[--]=ARGS_REMAINDER
)

parse_args ARGS "$@" || usage
(( ${#ARGS_REMAINDER[@]} > 0 )) || usage

ARG_VERB="${ARGS_REMAINDER[0]}"


#
# main
#

eval "$(globaltraps)"

case "$ARG_VERB" in
benchmark|run)
	(( ${#ARGS_REMAINDER[@]} == 2 )) || usage
	ARG_TEST="${ARGS_REMAINDER[1]}"

	pts_setup_part
	pts_restore
	pts_install "$ARG_TEST"
	pts_run "$ARG_TEST"
	;;

install)
	(( ${#ARGS_REMAINDER[@]} == 2 )) || usage
	ARG_TEST="${ARGS_REMAINDER[1]}"

	pts_restore
	pts_install --install-only "$ARG_TEST"
	;;

*)
	pts_restore
	phoronix-test-suite "${ARGS_REMAINDER[@]}"
	;;
esac
