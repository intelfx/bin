#!/bin/bash -e

. $HOME/bin/lib/lib.sh || exit

SCRIPT_DIR="$HOME/build/my/proton-ge"
SOURCE_DIR="$SCRIPT_DIR/proton-ge-custom"
BUILD_DIR="/mnt/ssd/Scratch/proton-ge"

CMD=()
ARGS=()
unset TAG
unset PATCH_VERSION

while (( $# )); do
	declare k v n
	if get_arg k v n --build-tag -- "$@"; then
		TAG="$v"
		shift "$n"
	elif get_arg k v n -v -- "$@"; then
		PATCH_VERSION="$v"
		shift "$n"
	else
		ARGS+=( "$1" )
		shift 1
	fi
done

CMD=(
	--enable-ccache
	--container-engine=podman
)

SOURCE_TAG="$(cd "$SOURCE_DIR" && git describe --tags --abbrev=0)"

if [[ ${TAG+set} ]]; then
	CMD+=( --build-name="$SOURCE_TAG-$TAG" )
else
	CMD+=( --build-name="$SOURCE_TAG" )
fi

if [[ ${PATCH_VERSION+set} ]]; then
	log "Forcing patches v${PATCH_VERSION}"
else
	PATCH_VERSION=8
	log "Using patches v${PATCH_VERSION}"
fi

PATCH_DIR="$SCRIPT_DIR/patches${PATCH_VERSION}"
if ! [[ -d "$PATCH_DIR" ]]; then
	die "Patch directory does not exist: $PATCH_DIR"
fi

shopt -s nullglob
set -x
(
	cd "$SOURCE_DIR"
	git reset --hard; git clean -fxd
	git submodule foreach --recursive 'git reset --hard; git clean -fxd'
	git submodule update --init --recursive --progress
	./patches/protonprep-valve-staging.sh |& tee "$BUILD_DIR/protonprep-valve-staging.log"
	for p in "$PATCH_DIR"/*.patch; do
		if [[ $p == *WIP* ]]; then
			continue
		fi
		git apply -3 "$p"
	done
	for p in "$PATCH_DIR/openfst"/*.patch; do
		if [[ $p == *WIP* ]]; then
			continue
		fi
		git -C openfst apply -3 "$p"
	done
)

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

"$SOURCE_DIR/configure.sh" "${CMD[@]}" "${ARGS[@]}"
sed -r "/^ENABLE_CCACHE := 1/{
aexport CCACHE_BASEDIR := $BUILD_DIR
aexport CCACHE_CONFIGPATH := $SCRIPT_DIR/ccache.conf
}" -i Makefile

make all redist
put *.tar.* '/mnt/data/Files/shared/dist/misc/deck/proton'
