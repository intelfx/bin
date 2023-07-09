#!/bin/bash -e

SOURCE_DIR="$(dirname "$BASH_SOURCE")/proton-ge-custom"
BUILD_DIR="$(pwd)"

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
	fi
done

CMD=(
	--enable-ccache
	--container-engine=podman
)

if [[ ${TAG+set} ]]; then
	CMD+=( --build-name="$(cd "$SOURCE_DIR" && git describe --tags)-$TAG" )
fi

shopt -s nullglob
set -x
(
	cd "$SOURCE_DIR"
	git reset --hard; git clean -fxd
	git submodule foreach 'git reset --hard; git clean -fxd'
	./patches/protonprep-valve-staging.sh |& tee "$BUILD_DIR/protonprep-valve-staging.log"
	for p in ../patches8/*.patch; do
		git apply -3 "$p"
	done
	for p in ../patches-openfst/*.patch; do
		git -C openfst apply -3 "../$p"
	done
)
"$SOURCE_DIR/configure.sh" "${CMD[@]}" "${ARGS[@]}"
make all redist
put *.tar.* '/mnt/data/Files/shared/dist/misc/deck/proton'
