#!/bin/bash

. lib.sh || exit

_usage() {
	cat <<EOF
Usage: ${0##*/} <repo name> <target directory>
EOF
}

(( $# == 2 )) || usage "Expected 2 arguments, got $#"

REPO_NAME="$1"
REPO_DIR="$2"
log "Rebuilding [$REPO_NAME] into \"$REPO_DIR\""

[[ -d "$REPO_DIR" ]] || die "\"$REPO_DIR\" does not exist"
[[ -w "$REPO_DIR" ]] || die "\"$REPO_DIR\" is not writable"

# `sort -r` orders longer pkgnames before shorter ones
# this is significant because we match package files using pkgnames as prefixes, so e. g. pkgname="clion" will also match a "clion-cmake-..." package
if ! pacman -Sql "$REPO_NAME" | sort -r | readarray -t REPO_PKGS; then
	die "$REPO_NAME could not be listed"
fi

CACHE_DIRS=()
cache_dir() {
	if [[ "$1" && -d "$1" ]]; then
		CACHE_DIRS+=( "$1" )
		(( ++ok ))
	else
		(( ++rej ))
	fi
}

ok=0
rej=0
pacman-conf CacheDir | while read dir; do
	cache_dir "$dir"
done
log "/etc/pacman.conf - $ok cache directories read, $rej cache directories rejected"

ok=0
rej=0
(
	. /etc/makepkg.conf >&2
	echo "$PKGDEST"
) | read dir
cache_dir "$dir"
log "/etc/makepkg.conf - $ok cache directories read, $rej cache directories rejected"

declare -A PKG_VERSIONS
declare -A PKG_FILES
declare -A FILES_CONSUMED
try_copy() {
	local file="$1"
	local pkgname="$2"
	local pkgver="$3"

	if [[ "$file" == *.sig ]]; then
		return
	fi

	if [[ "$file" == *.part ]]; then
		return
	fi

	if [[ "${FILES_CONSUMED["$file"]}" ]]; then
		return
	fi
	FILES_CONSUMED["$file"]=1

	if ! [[ "${PKG_VERSIONS["$pkgname"]}" ]]; then
		log "[$pkg] ${file}: first time seen, accepting"
	elif (( $(vercmp "${PKG_VERSIONS["$pkgname"]}" "$pkgver") < 0 )); then
		log "[$pkg] ${file}: new pkgver ($pkgver) > last pkgver (${PKG_VERSIONS["$pkgname"]}), accepting"
	else
		log "[$pkg] ${file}: not new enough"
		return 0
	fi

	PKG_VERSIONS["$pkgname"]="$pkgver"
	PKG_FILES["$pkgname"]="$file"
}

shopt -s extglob
shopt -s nullglob
for pkg in "${REPO_PKGS[@]}"; do
	expac -S '%n %v %a' "$REPO_NAME/$pkg" | read pkg_name pkg_ver pkg_arch

	for dir in "${CACHE_DIRS[@]}"; do
		for f in "$dir"/"$pkg_name-$pkg_ver-$pkg_arch".pkg.tar*; do
			try_copy "$(realpath -s "$f")" "$pkg_name" "$pkg_ver"
		done
	done
done

cp -v --preserve=timestamps "${PKG_FILES[@]}" -t "$REPO_DIR"

log "Salvaged ${#PKG_FILES[@]} packages out of ${#REPO_PKGS[@]} in the repo"
