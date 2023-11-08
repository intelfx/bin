#!/bin/bash -e

SCRIPT_DIR="$HOME/build/my/proton-ge"
SOURCE_DIR="$SCRIPT_DIR/proton-ge-custom"
BUILD_DIR="/mnt/ssd/Scratch/proton-ge"

CMD=()
ARGS=()
unset TAG

while (( $# )); do
	if [[ $1 == --build-tag ]]; then
		TAG="$2"
		shift 2
	elif [[ $1 == --build-tag=* ]]; then
		TAG="${1#*=}"
		shift
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

PATCH_DIR="$SCRIPT_DIR/patches8"
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
		git apply -3 "$p"
	done
	for p in "$PATCH_DIR/openfst"/*.patch; do
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
