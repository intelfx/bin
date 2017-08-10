#!/bin/bash

# THE IDEA:
# 'tar' and 'du' has the same options for excluding files.

declare -A ARCHIVERS
ARCHIVERS=(
	[xz]="xz -9e"
	[xzfast]="xz -1"
	[gz]="gzip -9"
	[gzfast]="gzip -1"
	[bz2]="bzip2 -9"
	[7z]="7z a -t7z -mx=9 -ms=on -mf=on -mhc=on -mmt=2 -m0=LZMA2:a=1:d=30"
	[lzop]="lzop"
	[lzopfast]="lzop -1"
	[lzopbest]="lzop -9"
	[lrzip]="lrzip"
)

declare -A TARLESS
TARLESS=(
	[7z]="1"
)

function log() {
	echo "$*" >&2
}

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

Usage: $0 [-fn] [-o|--output OUTPUT] [-N|--name NAME] [-c|--compressor COMPRESSOR] [-O|--compressor-options OPTIONS]

Options:
	-o, --output OUTPUT
		Write archive to OUTPUT; may be directory or file.

	-N, --name NAME
		Use NAME for logging.
		Also used as archive file name stem, if OUTPUT is a directory.

	-c, --compressor COMPRESSOR
		Explicitly set compressing filter to COMPRESSOR.
		Available options:
$(get_compressors "		 * ")

	-n, --no-compressor
		Explicitly disable compression.

	-f, --force
		Allow overwriting the output file.

	-O, --compressor-options OPTIONS
		Options for the compressor.

EOF
}

ARGS=$(getopt --long "output:,name:,compressor:,no-compressor,force,compressor-options" -- "o:N:nc:fO:" "$@")
if (( "$?" )); then
	exit 1
fi

eval set -- "$ARGS"

# Defaults.

ARCHIVER=""
PV_OPTS="-pba -W"
PV_SECONDSTAGE_OPTS="-ba -W"
ARCHIVER_OPTS=""

while true; do
	case "$1" in
		-f|--force)
			FORCE=1
			;;
		-o|--output)
			shift
			OUTPUT="$1"

			if [[ ! "$OUTPUT" ]]; then
				log "E: empty output name."
				exit 1
			fi

			if [[ "$OUTPUT" != "-" && ! -d "$OUTPUT" ]]; then
				if [[ -z "$NAME" ]]; then
					NAME="${OUTPUT##*/}" # use output as name: remove directories
					NAME="${NAME%%.*}" # use output as name: remove extensions

					log "N: defaulting name to '$NAME' from output file stem."
				fi

				if [[ "$OUTPUT" =~ \.([^.]*)$ ]]; then
					EXTENSION="${BASH_REMATCH[1]}"

					if [[ -z "$ARCHIVER" && -n "${ARCHIVERS[$EXTENSION]}" ]]; then
						ARCHIVER="$EXTENSION"

						log "N: defaulting archiver to '$ARCHIVER' from output file extension."
					fi
				fi
			fi
			;;
		-N|--name)
			shift
			NAME="$1"
			;;
		-n|--no-compressor)
			ARCHIVER=""
			;;
		-c|--compressor)
			shift
			if [[ "${ARCHIVERS[$1]}" ]]; then
				ARCHIVER="$1"
			else
				log "E: invalid archiver '$1'."
				exit 1
			fi
			;;
		-O|--compressor-options)
			shift
			ARCHIVER_OPTS="$1"
			;;
		--)
			shift # we won't get to the shift in the end of loop
			break
			;;
		*)
			log "E: wrong option."
			usage
			exit 1
			;;
	esac

	shift
done

if ! (( $# )); then
	log "E: No source files to archive."
	usage
	exit 1
fi

if [[ -z "$NAME" ]]; then
	if (( $# == 1 )); then
		NAME="$(basename "$1")" # use first input name: remove directories

		log "N: defaulting name to '$NAME' from the only input."
	else
		NAME="files"

		log "N: defaulting name to '$NAME'."
	fi
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

if [[ "$OUTPUT" != "-" ]]; then
	if [[ -z "$OUTPUT" ]]; then
		OUTPUT="${NAME}${EXTENSION}"

		log "N: defaulting output to '$OUTPUT'."
	elif [[ -d "$OUTPUT" ]]; then
		OUTPUT+="/${NAME}${EXTENSION}"

		log "N: defaulting output to '$OUTPUT'."
	fi

	if [[ -d "$OUTPUT" ]]; then
		log "E: '$OUTPUT' exists and is a directory. Aborting."
		exit 1
	elif [[ -e "$OUTPUT" ]]; then
		if (( FORCE )); then
			if [[ -f "$OUTPUT" ]]; then
				log "W: '$OUTPUT' exists and is a regular file. Removing."
				rm -f "$OUTPUT"
			else
				log "W: '$OUTPUT' exists and is not a regular file. The archiver will decide what to do."
			fi
		else
			log "E: '$OUTPUT' exists. Pass '-f' to overwrite."
			exit 1
		fi
	fi
fi

function tar_and_archive_cmd() {
	local size="$(get_size "$@")"
	tar -c "$@" \
		| pv ${PV_OPTS}             -cN "Archiving   $NAME (tar)" -s "$size" \
		| $ARCHIVER_CMD $ARCHIVER_OPTS \
		| pv ${PV_SECONDSTAGE_OPTS} -WN "Compressing $NAME ($ARCHIVER_NAME)"
}

function tar_cmd() {
	local size="$(get_size "$@")"
	tar -c "$@" \
		| pv $PV_OPTS -N "$NAME" -s "$size"
}

if [[ "$ARCHIVER" ]]; then
	ARCHIVER_CMD="${ARCHIVERS["$ARCHIVER"]}"
	ARCHIVER_NAME="${ARCHIVER_CMD%% *}" # Select first word of the string (command name)

	if [[ "${TARLESS[$ARCHIVER]}" ]]; then
		if [[ "$OUTPUT" == "-" ]]; then
			log "E: writing to stdout is not supported with this archiver."
			exit 1
		else
			log "N: compressing and writing to '$OUTPUT'"
			$ARCHIVER_CMD $ARCHIVER_OPTS "${OUTPUT}" "$@"
		fi
	else
		if [[ "$OUTPUT" == "-" ]]; then
			log "N: compressing and writing to stdout"
			tar_and_archive_cmd "$@"
		else
			log "N: compressing and writing to '$OUTPUT'"
			tar_and_archive_cmd "$@" > "$OUTPUT"
		fi
	fi
else
	if [[ "$OUTPUT" == "-" ]]; then
		log "N: writing to stdout"
		tar_cmd "$@"
	else
		log "N: writing to '$OUTPUT'"
		tar_cmd "$@" > "$OUTPUT"
	fi
fi
