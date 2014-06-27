#!/bin/bash

# THE IDEA:
# 'tar' and 'du' has the same options for excluding files.

declare -A ARCHIVERS
ARCHIVERS=(
	[xz]="xz -9e"
	[gz]="gzip -9"
	[bz2]="bzip2 -9"
)

function get_compressors() {
	for compressor in "${!ARCHIVERS[@]}"; do
		echo "$1$compressor: '${ARCHIVERS[$compressor]}'"
	done
}

function get_size() {
	du --apparent-size -csb "$@" | tail -n1 | cut -d$'\t' -f1
}

function usage() {
	cat <<EOF
archive.sh -- a directory archiving tool

Usage: $0 [-fn] [-o OUTPUT] [-N NAME] [-c COMPRESSOR]

Options:
	-o OUTPUT
		Write archive to OUTPUT; may be directory or file.

	-N NAME
		Use NAME for logging.
		Also used as archive file name stem, if OUTPUT is a directory.

	-c COMPRESSOR
		Explicitly set compressing filter to COMPRESSOR.
		Available options:
$(get_compressors "		 * ")

	-n
		Explicitly disable compression.

	-f
		Allow overwriting the output file.

EOF
}

ARGS=$(getopt -- "o:N:nc:f" "$@")
if (( "$?" )); then
	exit 1
fi

eval set -- "$ARGS"

# Defaults.

ARCHIVER=""
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
			echo "E: wrong option."
			usage
			exit 1
			;;
	esac

	shift
done

if ! (( $# )); then
	echo "E: No source files to archive."
	usage
	exit 1
fi

if [[ -d "$OUTPUT" ]]; then
	OUTPUT+="/${NAME}.tar"
else
	if [[ -z "$NAME" ]]; then
		if [[ -n "$OUTPUT" ]]; then
			NAME="${OUTPUT##*/}" # use output as name: remove directories
			NAME="${NAME%%.*}" # use output as name: remove extensions
		else
			NAME="${1##*/}" # use first source directory as name: remove directories
		fi

		echo "N: defaulting name to '$NAME'."
	fi

	if [[ -z "$OUTPUT" ]]; then
		OUTPUT="${NAME}.tar" # use name as output

		echo "N: defaulting output to '$OUTPUT'."
	fi

	if (( FORCE )) && [[ -e "$OUTPUT" ]]; then
		echo "W: '$OUTPUT' exists and is not a directory. Overwriting."
		rm -f "$OUTPUT"
	fi

	if [[ -e "$OUTPUT" ]]; then
		echo "E: '$OUTPUT' exists and is not a directory. Pass '-f' to overwrite."
		exit 1
	fi

fi

if [[ -z "$ARCHIVER" && "$OUTPUT" =~ \.tar\.(.*)$ ]]; then
	ARCHIVER="${BASH_REMATCH[1]}"

	echo "N: defaulting archiver to '${BASH_REMATCH[1]}'."
fi

if [[ "$ARCHIVER" && "${ARCHIVERS["$ARCHIVER"]}" ]]; then
	ARCHIVER_EXT="$ARCHIVER"
	ARCHIVER_CMD="${ARCHIVERS["$ARCHIVER"]}"
	ARCHIVER_NAME="${ARCHIVER%% *}" # Select first word of the string (command name)

	echo "N: compressing and writing to '${OUTPUT}.${ARCHIVER_EXT}'"

	tar -c "$@" \
		| pv ${PV_OPTS}             -cN "Archiving   $NAME (tar)" -s $(get_size "$@") \
		| $ARCHIVER_CMD \
		| pv ${PV_SECONDSTAGE_OPTS} -WN "Compressing $NAME ($ARCHIVER_NAME)" \
		> "${OUTPUT}.${ARCHIVER_EXT}"
else
	echo "N: writing to '${OUTPUT}'"

	tar -c "$@" \
		| pv $PV_OPTS -N "$NAME" -s $(get_size "$@") \
		> "${OUTPUT}"
fi
