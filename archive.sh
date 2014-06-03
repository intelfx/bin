#!/bin/bash

# THE IDEA:
# 'tar' and 'du' has the same options for excluding files.

declare -A ARCHIVERS
ARCHIVERS=(
	[xz]="xz -9e"
	[gz]="gzip -9"
	[bz2]="bzip2 -9"
)

function get_size() {
	du --apparent-size -sb "$@" | cut -d$'\t' -f1
}

ARGS=$(getopt -- "o:N:nc:f" "$@")
if (( "$?" )); then
	exit 1
fi

eval set -- "$ARGS"

# Defaults.

ARCHIVER='xz'
DIRECTORY="$(pwd)"
PV_OPTS="-pba"
PV_SECONDSTAGE_OPTS="-b"

while true; do
	case "$1" in
		-f)
			FORCE=1
			;;
		-o)
			shift
			OUTPUT="$1"
			;;
		-N)
			shift
			NAME="$1"
			;;
		-n)
			ARCHIVER=""
			;;
		-c)
			shift
			ARCHIVER="$1"
			;;
		--)
			shift # we won't get to the shift in the end of loop
			break
			;;
		*)
			cat <<- EOF
			The archiver.
			Options:
				-o <output directory or file>
				-N <archive name>
				-c <compressor name: ${!ARCHIVERS[@]}>
				-n (do not compress)

			Non-options shall be directory names and common options of "du" and "tar" (e. g. --exclude).
			EOF
			exit 1
			;;
	esac

	shift
done

if ! (( $# )); then
	echo "==== Error: no directory arguments given"
	exit 1
fi

[[ -z "$NAME" ]] && NAME="$(basename "$1")"

if [[ -d "$OUTPUT" ]]; then
	OUTPUT+="/${NAME}.tar"
else
	if (( FORCE )) && [[ -e "$OUTPUT" ]]; then
		echo "==== Warning: output ($OUTPUT) exists and --force is given, removing"
		rm -vf "$OUTPUT"
	fi

	if [[ -e "$OUTPUT" ]]; then
		echo "==== Error: output ($OUTPUT) exists and is not a directory"
		exit 1
	fi
	
	if [[ -z "$OUTPUT" ]]; then
		OUTPUT="${NAME}.tar"
	fi
fi

echo "---- Destination file: $OUTPUT"

if [[ "$ARCHIVER" && "${ARCHIVERS["$ARCHIVER"]}" ]]; then
	ARCHIVER_EXT="$ARCHIVER"
	ARCHIVER_CMD="${ARCHIVERS["$ARCHIVER"]}"
	ARCHIVER_NAME="${ARCHIVER%% *}" # Select first word of the string (command name)

	tar -c "$@" \
		| pv ${PV_OPTS}             -cN "Archiving   $NAME (tar)" -s $(get_size "$@") \
		| $ARCHIVER_CMD \
		| pv ${PV_SECONDSTAGE_OPTS} -WN "Compressing $NAME ($ARCHIVER_NAME)" \
		> "${OUTPUT}.${ARCHIVER_EXT}"
else
	tar -c "$@" \
		| pv $PV_OPTS -N "$NAME" -s $(get_size "$@") \
		> "${OUTPUT}"
fi
