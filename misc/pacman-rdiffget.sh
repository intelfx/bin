#!/bin/bash

. lib.sh || exit

usage() {
	cat <<EOF
Usage: $0 [RDIFF-OPTIONS...] <REPO-NAME> <SRC-DIR>

Attempt to fetch updated packages in <REPO-NAME> from <SRC-DIR>, using files
in local pacman cache as delta bases.

Options:
  <REPO-NAME>		Name of a locally configured pacman repository
  <SRC-DIR>		Remote path (user@host:path) to the directory
			with files in <REPO-NAME>
  RDIFF-OPTIONS		Options accepted by rdiff
EOF
}

if ! (( $# >= 2 )); then
	usage "Not enough parameters (got $#, expected at least 2)"
fi

eval "$(globaltraps)"

REPO_NAME="${@: -2:1}"
SRC_DIR="${@: -1:1}"
RDIFF_ARGS=( "${@:1:$#-2}" )

pacconf CacheDir | readarray -t DEST_DIRS
if ! [[ ${DEST_DIRS+set} ]]; then
	die "CacheDir= not set in /etc/pacman.conf"
fi
DEST_DIR="${DEST_DIRS[0]}"

SRC_DIR="${SRC_DIR%%/}"
DEST_DIR="${DEST_DIR%%/}"

log "Repo name:   $REPO_NAME"
log "Source:      $SRC_DIR"
log "Destination: $DEST_DIR"

TRANSFERS=()
TRANSFERRED_FILES=()

expac -S '%r\t%n\t%v\t%f' | while IFS=$'\t' read p_repo p_name p_ver p_file; do
	if [[ $p_repo != $REPO_NAME ]]; then
		continue
	fi
	# if we have an uptodate file, skip
	if [[ -e "$DEST_DIR/$p_file" ]]; then
		continue
	fi
	# if we have an uptodate uncompressed file, skip
	p_uncomp="${p_file//.pkg.tar*/.pkg.tar}"
	if [[ -e "$DEST_DIR/$p_uncomp" ]]; then
		continue
	fi
	# find old local files for given package
	p_local_best_file=
	p_local_best_ver=
	find "$DEST_DIR" -type f \( -name "$p_name-*.pkg.tar*" -and -not -name '*.sig' \) -printf '%P\n' | while read p_local_file; do
		# extract metadata from .PKGINFO to avoid parsing file name
		# `--occurrence=1` to exit after first .PKGINFO is processed, do not scan the rest of the archive
		tar -xaf "$DEST_DIR/$p_local_file" .PKGINFO -O --occurrence=1 | sed -nr 's#^(pkgname|pkgver) = (.+)$#\1 \2#p' | while read key value; do
			if [[ "$key" == pkgname ]]; then
				p_local_name="$value"
			elif [[ "$key" = pkgver ]]; then
				p_local_ver="$value"
			fi
		done

		# filter prefix matches
		# (e. g. we could have found a "foo-bar-123-1-any.pkg.tar" when $p_name is "foo")
		if [[ $p_local_name != $p_name ]]; then
			continue
		fi

		# find best (most recent) local file
		# accept file if no match yet
		if [[ ! $p_local_best_file ]]; then
			p_local_best_file="$p_local_file"
			p_local_best_ver="$p_local_ver"
			continue
		fi
		# accept file if newer
		cmp="$(vercmp "$p_local_best_ver" "$p_local_ver")"
		if (( $cmp < 0 )); then
			p_local_best_file="$p_local_file"
			p_local_best_ver="$p_local_ver"
			continue
		fi
		# accept file if it is the same version, but uncompressed
		if (( $cmp == 0 )) && [[ $p_local_best_file != *.pkg.tar ]] && [[ $p_local_file == *.pkg.tar ]]; then
			p_local_best_file="$p_local_file"
			p_local_best_ver="$p_local_ver"
			continue
		fi
	done
	if [[ $p_local_best_file ]]; then
		#log "$p_repo/$p_name: remote=$p_ver best local=$p_local_best_ver ($p_local_best_file)"
		TRANSFERS+=( "$p_name"$'\t'"$p_file"$'\t'"$p_local_best_file" )
	fi
done

#TARGET_DIR="/home/intelfx/newfiles"
#mkdir -p "$TARGET_DIR"

INCOMPLETE_FILE=
cleanup() {
	rm -vf "$INCOMPLETE_FILE"
}
trap cleanup EXIT

for t in "${TRANSFERS[@]}"; do
	IFS=$'\t' read p_name p_remote p_local <<<"$t"

	log "$p_name: $p_remote -> $p_local"

	# NOTE: we assume here that `rdiffget` will decompress files prior to transfer
	p_uncomp="${p_remote/.pkg.tar*/.pkg.tar}"
	INCOMPLETE_FILE="$DEST_DIR/$p_uncomp"
	rdiffget "${RDIFF_ARGS[@]}" "$SRC_DIR/$p_remote" "$DEST_DIR/$p_local"

	INCOMPLETE_FILE=
	TRANSFERRED_FILES+=( "$DEST_DIR/$p_uncomp" )
done

if [[ ${TRANSFERRED_FILES+set} ]]; then
	log "Transferred ${#TRANSFERRED_FILES[@]} files"
	print_array "${TRANSFERRED_FILES[@]}"
fi
