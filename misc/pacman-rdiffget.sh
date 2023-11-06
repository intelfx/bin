#!/bin/bash

. lib.sh || exit


#
# args and usage
#

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


#
# functions
#

# `expac -S` does not support restricting its output by repository name;
# sunrise by hand
expac_by_repo() {
	local expac_opts expac_args
	local expac_repo
	local k v n
	while (( $# )); do
		if get_arg k v n \
			-r --repo \
		-- "$@"; then
			expac_repo="$v"
			shift "$n"
		elif get_arg k v n \
			--config \
			-H --humanize \
			-d --delim \
			-l --listdelim \
			-t --timefmt \
		-- "$@"; then
			expac_opts+=( "${@:1:$n}" )
			shift "$n"
		elif get_flag k n \
			-Q --query \
			-S --sync \
			-s --search \
			-g --group \
			-1 --readone \
			-p --file \
			-v --verbose \
			-V --version \
			-h --help \
		-- "$@"; then
			expac_opts+=( "${@:1:$n}" )
			shift "$n"
		else
			expac_args+=( "$1" )
			shift 1
		fi
	done

	if [[ ${expac_repo} ]]; then
		# prepend %r to the format string
		expac_args[0]="%r\t${expac_args[0]}"

		expac "${expac_opts[@]}" "${expac_args[@]}" \
		| sed -nr "s|^$expac_repo"$'\t'"(.+)$|\1|p"
	else
		expac "${expac_opts[@]}" "${expac_args[@]}"
	fi
}

#
# main
#

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

# Find installed packages that exist in repo
grep -Fxf \
	<(expac -Q '%n') \
	<(expac_by_repo -r "$REPO_NAME" -S '%n') \
| readarray -t packages

if ! [[ ${packages+set} ]]; then
	exit 0
fi

# Find local and remote versions of candidate packages
declare -A LOCAL_PKG_VER
declare -A REPO_PKG_VER
declare -A REPO_PKG_FILE
expac -Q '%n\t%v' "${packages[@]}" \
| while IFS=$'\t' read p_name p_ver; do
	LOCAL_PKG_VER[$p_name]="$p_ver"
done
expac_by_repo -r "$REPO_NAME" -S '%n\t%v\t%f' "${packages[@]}" \
| while IFS=$'\t' read p_name p_ver p_file; do
	REPO_PKG_VER[$p_name]="$p_ver"
	REPO_PKG_FILE[$p_name]="$p_file"
done

# Find files that can be delta-retrieved from remote
for p_name in "${packages[@]}"; do
	p_ver="${REPO_PKG_VER[$p_name]}"
	p_local_ver="${LOCAL_PKG_VER[$p_name]}"
	p_file="${REPO_PKG_FILE[$p_name]}"
	p_uncomp="${p_file/.pkg.tar*/.pkg.tar}"

	# if remote package is not an update, skip
	cmp="$(vercmp "$p_ver" "$p_local_ver")"
	if ! (( cmp > 0 )); then
		continue
	fi
	# if we have an uptodate file, skip
	if [[ -e "$DEST_DIR/$p_file" ]]; then
		log "$p_name: already exists"
		TRANSFERRED_FILES+=( "$DEST_DIR/$p_file" )
		continue
	fi
	# if we have an uptodate uncompressed file, skip
	if [[ -e "$DEST_DIR/$p_uncomp" ]]; then
		log "$p_name: already exists (uncompressed)"
		TRANSFERRED_FILES+=( "$DEST_DIR/$p_uncomp" )
		continue
	fi
	# find old local files for given package
	p_local_best_file=
	p_local_best_ver=
	find "$DEST_DIR" \
		-type f \
		\( -name "$p_name-*.pkg.tar*" -and -not -name '*.sig' -and -not -name '*.part' \) \
		-printf '%P\n' \
	| while read p_local_file; do
		# extract metadata from .PKGINFO to avoid parsing file name
		# `--occurrence=1` to exit after first .PKGINFO is processed, do not scan the rest of the archive
		tar -xaf "$DEST_DIR/$p_local_file" .PKGINFO -O --occurrence=1 \
		| sed -nr 's#^(pkgname|pkgver) = (.+)$#\1 \2#p' \
		| while read key value; do
			if [[ "$key" == pkgname ]]; then
				p_local_name="$value"
			elif [[ "$key" = pkgver ]]; then
				p_local_ver="$value"
			else
				die "Bad .PKGINFO line: key=$key value=$value"
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
		if (( $cmp == 0 )) && [[ $p_local_best_file == *.pkg.tar.* ]] && [[ $p_local_file == *.pkg.tar ]]; then
			p_local_best_file="$p_local_file"
			p_local_best_ver="$p_local_ver"
			continue
		fi
	done
	if [[ $p_local_best_file ]]; then
		TRANSFERS+=( "$p_name"$'\t'"$p_file"$'\t'"$p_local_best_file"$'\t'"$p_uncomp" )
	fi
done

for t in "${TRANSFERS[@]}"; do
	IFS=$'\t' read p_name p_file p_local_file p_uncomp <<<"$t"

	log "$p_name: transferring: $p_file"
	log "$p_name:         base: $p_local_file"

	if [[ -e "$DEST_DIR/$p_file" ]]; then
		log "$p_name: already exists"
		continue
	fi
	if [[ -e "$DEST_DIR/$p_uncomp" ]]; then
		log "$p_name: already exists (uncompressed)"
		continue
	fi
	if [[ $p_file == $p_local_file ]]; then
		log "$p_name: ?!: local == remote"
		continue
	fi
	if [[ $p_uncomp == $p_local_file ]]; then
		log "$p_name: ?!: local == remote (uncompressed)"
		continue
	fi

	rdiffget "${RDIFF_ARGS[@]}" "$SRC_DIR/$p_file" "$DEST_DIR/$p_local_file"
	# NOTE: we assume here that `rdiffget` will uncompress file to transfer
	TRANSFERRED_FILES+=( "$DEST_DIR/$p_uncomp" )
done

if [[ ${TRANSFERRED_FILES+set} ]]; then
	log "Transferred ${#TRANSFERRED_FILES[@]} files"
	print_array "${TRANSFERRED_FILES[@]}"
fi
