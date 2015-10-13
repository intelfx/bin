#!/bin/bash

# THE IDEA:
# 'tar' and 'du' has the same options for excluding files.

declare -A ARCHIVERS
ARCHIVERS=(
	[xz]="xz -9e"
	[gz]="gzip -9"
	[bz2]="bzip2 -9"
	[7z]="7z a -t7z -mx=9 -ms=on -mf=on -mhc=on -mmt=2 -m0=LZMA2:a=1:d=30"
	[lzop]="lzop"
	[lrzip]="lrzip"
)

declare -A TARLESS
TARLESS=(
	[7z]="1"
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

			if [[ ! -d "$OUTPUT" ]]; then
				if [[ -z "$NAME" ]]; then
					NAME="${OUTPUT##*/}" # use output as name: remove directories
					NAME="${NAME%%.*}" # use output as name: remove extensions

					echo "N: defaulting name to '$NAME' from output file stem."
				fi

				if [[ "$OUTPUT" =~ \.([^.]*)$ ]]; then
					EXTENSION="${BASH_REMATCH[1]}"

					if [[ -z "$ARCHIVER" && -n "${ARCHIVERS[$EXTENSION]}" ]]; then
						ARCHIVER="$EXTENSION"

						echo "N: defaulting archiver to '$ARCHIVER' from output file extension."
					fi
				fi
			fi
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
			if [[ "${ARCHIVERS[$1]}" ]]; then
				ARCHIVER="$1"
			else
				echo "E: invalid archiver '$1'."
				exit 1
			fi
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

if [[ -z "$NAME" ]]; then
	NAME="$(basename "$1")" # use first source directory as name: remove directories

	echo "N: defaulting name to '$NAME' from first source directory."
fi

if [[ "$ARCHIVER" ]]; then
	if [[ "${TARLESS[$ARCHIVER]}" ]]; then
		EXTENSION=".$ARCHIVER"
	else
		EXTENSION=".tar.$ARCHIVER"
	fi
else
	EXTENSION=".tar"
fi

if [[ -z "$OUTPUT" ]]; then
	OUTPUT="${NAME}${EXTENSION}"

	echo "N: defaulting output to '$OUTPUT'."
elif [[ -d "$OUTPUT" ]]; then
	OUTPUT+="/${NAME}${EXTENSION}"

	echo "N: defaulting output to '$OUTPUT'."
fi

if [[ -e "$OUTPUT" ]]; then
	if (( FORCE )); then
		echo "W: '$OUTPUT' exists and is not a directory. Overwriting."
		rm -f "$OUTPUT"
	else
		echo "E: '$OUTPUT' exists and is not a directory. Pass '-f' to overwrite."
		exit 1
	fi
fi

if [[ "$ARCHIVER" ]]; then
	ARCHIVER_CMD="${ARCHIVERS["$ARCHIVER"]}"
	ARCHIVER_NAME="${ARCHIVER_CMD%% *}" # Select first word of the string (command name)

	echo "N: compressing and writing to '$OUTPUT'"

	if [[ "${TARLESS[$ARCHIVER]}" ]]; then
		$ARCHIVER_CMD "${OUTPUT}" "$@"
	else
		tar -c "$@" \
			| pv ${PV_OPTS}             -cN "Archiving   $NAME (tar)" -s $(get_size "$@") \
			| $ARCHIVER_CMD \
			| pv ${PV_SECONDSTAGE_OPTS} -WN "Compressing $NAME ($ARCHIVER_NAME)" \
			> "${OUTPUT}"
	fi
else
	echo "N: writing to '${OUTPUT}'"

	tar -c "$@" \
		| pv $PV_OPTS -N "$NAME" -s $(get_size "$@") \
		> "${OUTPUT}"
fi
