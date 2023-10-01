#!/bin/bash

. lib.sh || exit

REPO=custom

declare -a PKGS
declare -A REPO_VER
declare -A ARCH_NAME
declare -A ARCH_VER
declare -A AUR_NAME
declare -A AUR_VER

log "Reading [$REPO]"
pacman -Sql "$REPO" | readarray -t PKGS

log "Querying official repos"
expac -S '%r %n %v' "${PKGS[@]}" | while read repo pkgname pkgver; do
	if [[ "$repo" == "$REPO" ]]; then
		dbg "----- $repo/$pkgname = $pkgver"
		REPO_VER["$pkgname"]="$pkgver"
	elif ! [[ "${ARCH_VER["$pkgname"]}" ]]; then
		# only accept first encountered official repo
		dbg "[off] $repo/$pkgname = $pkgver"
		ARCH_VER["$pkgname"]="$pkgver"
		ARCH_NAME["$pkgname"]="$repo/$pkgname"
	fi
done

log "Querying AUR"
aur query -t info "${PKGS[@]}" | jq -r '.results[] | "\(.Name) \(.Version)"' | while read pkgname pkgver; do
	dbg "[AUR] $pkgname = $pkgver"
	AUR_VER["$pkgname"]="$pkgver"
	AUR_NAME["$pkgname"]="aur/$pkgname"
done

vergreater() {
	(( $(vercmp "$@") > 0 ))
}

(
echo "RepoName RepoVer SourceVer Source"
for pkgname in "${PKGS[@]}"; do
	pkgver="${REPO_VER[$pkgname]}"
	archver="${ARCH_VER[$pkgname]}"
	aurver="${AUR_VER[$pkgname]}"

	if [[ $archver ]] && vergreater $archver $pkgver; then
		echo "$pkgname $pkgver $archver ${ARCH_NAME[$pkgname]}"
	elif [[ $aurver ]] && vergreater $aurver $pkgver; then
		echo "$pkgname $pkgver $aurver ${AUR_NAME[$pkgname]}"
	fi
done
) | column -Lt
