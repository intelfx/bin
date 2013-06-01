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

ARGS=$(getopt -- "D:N:na:" "$@")
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
		-D)
			shift
			DIRECTORY="$1"
			shift
			;;
		-N)
			shift
			NAME="$1"
			shift
			;;
		-n)
			ARCHIVER=""
			shift
			;;
		-a)
			shift
			ARCHIVER="$1"
			shift
			;;
		--)
			shift
			break
			;;
		*)
			cat <<- EOF
			The archiver.
			Options:
				-D <output directory>
				-N <archive name>
				-a <compressor name: ${!ARCHIVERS[@]}>
				-n - do not compress

			Non-options shall be directory names and common options of "du" and "tar" (e. g. --exclude).
			EOF
			exit 1
			;;
	esac
done

(( $# )) || exit 1

[[ -z "$NAME" ]] && NAME="$1"
NAME="$(basename "$NAME")"

OUTPUT="${DIRECTORY}/${NAME}.tar"

echo "---- Destination file: $OUTPUT"

if [[ "$ARCHIVER" && "${ARCHIVERS["$ARCHIVER"]}" ]]; then
	ARCHIVER_EXT="$ARCHIVER"
	ARCHIVER_CMD="${ARCHIVERS["$ARCHIVER"]}"
	ARCHIVER_NAME="${ARCHIVER%% *}" # Select first word of the string (command name)

	tar -c "$@" \
		| pv $PV_OPTS -cN "Archiving $NAME (tar)" -s $(get_size "$@") \
		| $ARCHIVER_CMD \
		| pv ${PV_SECONDSTAGE_OPTS} -cN "Compressing $NAME ($ARCHIVER_NAME)" \
		> "${OUTPUT}.${ARCHIVER_EXT}"
else
	tar -c "$@" \
		| pv $PV_OPTS -N "$NAME" -s $(get_size "$@") \
		> "${OUTPUT}"
fi
