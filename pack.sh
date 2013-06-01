#!/bin/bash

# For the cron
[[ "$PS1" ]] || source /etc/profile

SIGLIST="STOP"
DESTDIR="/tmp/cache-$USER"
ARCDIR="$HOME/__linux"
LOCKFILE="$ARCDIR/worker.lock"

#SUFFIX='.gz'
#COMPRESSOR='--gzip'

touch "$LOCKFILE"
exec 4<"$LOCKFILE"
if ! flock -x -n 4; then
	echo "==== Could not acquire the lock. Bailing out"
	exit 0
fi

mkdir -p "$DESTDIR" "$ARCDIR"

if [ "$1" == "quiet" ]; then
	QUIET_CHECK=1 # Bail out instead of killing if a directory is busy
	shift
fi

# $1: "read" - suspend offending processes,
#     "write" - kill offending processes
function check_kill() {
	[ -d "$SOURCE" ] || return 0

	PIDS=$(lsof +D "$SOURCE" -t)
	if [ -n "$PIDS" ]; then
		echo -n "---- Used by following PIDs:"
		for PID in $PIDS; do
			echo -n " $PID($(ps -o comm= c $PID))"
		done
		echo ""

		if (( "$QUIET_CHECK" )); then
			echo "==== Skipping busy directory"
			return 1
		fi

		case "$1" in
		write)
			SIGLIST="QUIT TERM KILL"
			;;
		read)
			SIGLIST="STOP"
			;;
		esac

		for SIGNAL in $SIGLIST; do
			echo "---- Killing with $SIGNAL"
			kill -$SIGNAL $PIDS
			KILLED_PIDS="$PIDS"
			KILLED_SIGNAL="$SIGNAL"
			sleep 2

			# Reread, we may have somebody still reading the dir
			PIDS=$(lsof +D "$SOURCE" -t)
			[ -z "$PIDS" ] && break
		done

		if [ -n "$PIDS" ]; then
			echo -n "==== Not all readers eliminated. Used by following PIDs:"
			for PID in $PIDS; do
				echo -n " $PID($(ps -o comm= c $PID))"
			done
			echo ""

			if [ "$1" == "write" ]; then
				echo "==== Skipping busy directory"
				return 1
			fi
		fi
	fi
}

function resume_processes() {
	if [ "$KILLED_SIGNAL" == "STOP" ]; then
		echo -n "---- Continuing the following PIDs:"
		for PID in $KILLED_PIDS; do
			echo -n " $PID($(ps -o comm= c $PID))"
		done
		echo ""

		echo "---- Killing with CONT"
		kill -CONT $KILLED_PIDS
	fi
	unset KILLED_SIGNAL KILLED_PIDS
}

function cleanup_stale() {
	echo "---- Cleaning up stale archive files"
	rm -f "$ARCFILE"*.new
}

function cleanup_dest() {
	echo "---- Resetting storage"
	rm -rf "$SOURCE"
	rm -rf "$DESTINATION"
}

function cleanup_all() {
	echo "---- Resetting archive and storage"
	rm -f "$ARCFILE"*
	rm -rf "$SOURCE"
	rm -rf "$DESTINATION"
}

function check_ready() {
	if [ -L "$SOURCE" -a "$(readlink "$SOURCE")" = "$DESTINATION" -a -d "$DESTINATION" ]; then
		echo "---- Link already exists: $DESTINATION"
		return 0
	else
		return 1
	fi
}

function prepare_destination() {
	if [ -r "$ARCFILE"* ]; then
		echo "---- Unpacking"
		rm -rf "$DESTINATION"
		tar -C "$DESTDIR" $COMPRESSOR -xaf "$ARCFILE"*
	elif [ -d "$(realpath -e "$SOURCE")" ]; then
		echo "---- Moving"
		rm -rf "$DESTINATION"
		mv -T "$SOURCE" "$DESTINATION"
	fi
	
	if [ ! -d "$DESTINATION" ]; then
		echo "---- Creating"
		mkdir -p -m700 "$DESTINATION"
	fi
}

function apply_link() {
		echo "---- Applying link"
		rm -rf "$SOURCE"
		ln -sf "$DESTINATION" "$SOURCE"
}

function save() {

	# Compare file lists
	local FILE_LISTS_EQUAL
	cmp -s /proc/self/fd/{4,5} 4< <(tar -C "$DESTDIR" $COMPRESSOR -tf "${ARCFILE}.tar${SUFFIX}" | sed -re 's#/$##') \
		                       5< <(cd "$DESTDIR"; find "$dirbase") && FILE_LISTS_EQUAL=1

	if (( "$FILE_LISTS_EQUAL" )) && tar -C "$DESTDIR" $COMPRESSOR -df "${ARCFILE}.tar${SUFFIX}" &>/dev/null; then
		echo "==== Saved copy is up-to-date, not rewriting"
	else
		echo "---- Saving"
		eval tar -C "$DESTDIR" $COMPRESSOR -cf "${ARCFILE}.new.tar${SUFFIX}" "$dirbase"
		mv "${ARCFILE}.new.tar${SUFFIX}" "${ARCFILE}.tar${SUFFIX}"
	fi
}

TARGET="$1"
shift

for dirbase; do
	PROCESS_SELECTIVE=1
	eval "PROCESS_DIR_${dirbase}=1"
done

while read directory dirbase ; do
	echo "Processing directory $directory (base-name $dirbase)"

	if (( "$PROCESS_SELECTIVE" )); then
		SKIP=1
		if eval '(( "$PROCESS_DIR_'${dirbase}'" ))'; then
			SKIP=0
		fi
	else
		SKIP=0
	fi

	if (( "$SKIP" )); then
		echo "==== Skipped"
		continue
	fi

	SOURCE="$HOME/$directory"
	ARCFILE="$ARCDIR/$dirbase"
	DESTINATION="$DESTDIR/$dirbase"

	cleanup_stale

	case "$TARGET" in
	"")
		if ! check_ready; then
			prepare_destination
			check_kill write
			apply_link
		fi
		;;
	"reset")
		check_kill write
		cleanup_all
		;;
	"save")
		if check_ready; then
			check_kill read
			save
			resume_processes
		fi
		;;
	"save-reset")
		if check_ready; then
			check_kill read
			save
			resume_processes
		fi
		check_kill write
		cleanup_dest
		;;
	*)
		echo "err: invalid target \"$TARGET\""
		exit 1
		;;
	esac

done < <(cat ~/ramstor_config.txt)
