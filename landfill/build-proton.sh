#!/bin/bash -e

set -eo pipefail
shopt -s lastpipe
shopt -s nullglob

. $HOME/bin/lib/lib.sh

SCRIPT_DIR="$HOME/tmp/big/build/proton-ge"
SOURCE_DIR="$SCRIPT_DIR/proton-ge-custom"
BUILD_DIR="/mnt/local/Scratch/build/proton-ge"
CCACHE_DIR="/mnt/local/Scratch/cache/proton-ge/ccache"
SCCACHE_DIR="/mnt/local/Scratch/cache/proton-ge/sccache"  # TODO: unused
CARGO_HOME="$HOME/.cache/cargo"
# XXX: hack, this is what hardcoded in the patches
MARCH_ORIG="znver2"
CC_FLAGS_ORIG="-march=znver2"
RUST_FLAGS_ORIG="-Ctarget-cpu=znver2"

CMD=()
ARGS=()
unset TAG
unset PATCH_VERSION
unset ARG_MARCH
unset ARG_CFLAGS
unset ARG_RUSTFLAGS
unset CC_FLAGS
unset RUST_FLAGS

_usage() {
	cat <<EOF
Usage: $0 [--build-tag SUFFIX] [--march MARCH] [--cflags FLAGS] [--rustflags FLAGS] [-v PATCH-VERSION]

--build-tag SUFFIX	append -SUFFIX to the name of the build
--march MARCH		replace ${MARCH_ORIG@Q} in ${CC_FLAGS_ORIG@Q} and ${RUST_FLAGS_ORIG@Q} with given string
--cflags FLAGS		replace entire ${CC_FLAGS_ORIG@Q} with given string
--rustflags FLAGS	replace entire ${RUST_FLAGS_ORIG@Q} with given string
-v PATCH-VERSION	use given patchset instead of autodetected (7ge, 8ge, 9ge, 10ge, ...)
EOF
}

while (( $# )); do
	declare k v n
	if get_arg k v n --build-tag -- "$@"; then
		TAG="$v"
		shift "$n"
	elif get_arg k v n --march -- "$@"; then
		ARG_MARCH="$v"
		shift "$n"
	elif get_arg k v n --cflags -- "$@"; then
		ARG_CFLAGS="$v"
		shift "$n"
	elif get_arg k v n --rustflags -- "$@"; then
		ARG_RUSTFLAGS="$v"
		shift "$n"
	elif get_arg k v n -v -- "$@"; then
		PATCH_VERSION="$v"
		shift "$n"
	elif get_flag k n -h --help -- "$@"; then
		usage
		exit
	else
		ARGS+=( "$1" )
		shift 1
	fi
done

CMD=(
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
	case "$SOURCE_TAG" in
		GE-Proton10-*)
			PATCH_VERSION=10ge ;;
		GE-Proton9-*)
			PATCH_VERSION=9ge ;;
		GE-Proton8-*)
			PATCH_VERSION=8ge ;;
		GE-Proton7-*)
			PATCH_VERSION=7ge ;;
		proton-7.0-*)
			PATCH_VERSION=7 ;;
		*)
			die "Unknown source tag $SOURCE_TAG, cannot pick patches" ;;
	esac
	log "Using patches v${PATCH_VERSION}"
fi

PATCH_DIR="$SCRIPT_DIR/patches-${PATCH_VERSION}"
if ! [[ -d "$PATCH_DIR" ]]; then
	die "Patch directory does not exist: $PATCH_DIR"
fi

if [[ $ARG_MARCH ]]; then
	CC_FLAGS="${CC_FLAGS_ORIG/$MARCH_ORIG/$ARG_MARCH}"
	RUST_FLAGS="${RUST_FLAGS_ORIG/$MARCH_ORIG/$ARG_MARCH}"
fi
if [[ $ARG_CFLAGS ]]; then
	CC_FLAGS="$ARG_CFLAGS"
fi
if [[ $ARG_RUSTFLAGS ]]; then
	RUST_FLAGS="$ARG_RUSTFLAGS"
fi


(
	set -x
	shopt -s nullglob

	mkdir -p "$BUILD_DIR"
	cd "$SOURCE_DIR"
	git nuke
	git submodule update --init --recursive --progress

	if [[ -e ./patches/protonprep-valve-staging.sh ]]; then
		./patches/protonprep-valve-staging.sh |& tee "$BUILD_DIR/protonprep-valve-staging.log"
	fi

	find "$PATCH_DIR" -type f -name '*.patch' -printf '%P\n' | sort | while IFS='' read -r p; do
		if [[ $p == *WIP* ]]; then
			continue
		fi

		patch_subdir="$(dirname "$p")"
		patch_name="$(basename "$p")"
		log "applying: subdir ${patch_subdir@Q} patch ${patch_name@Q}"
		git -C "$patch_subdir" apply -3 "$PATCH_DIR/$p"
	done
)

if [[ $CC_FLAGS || $RUST_FLAGS ]]; then
	: ${CC_FLAGS=$CC_FLAGS_ORIG}
	: ${RUST_FLAGS=$RUST_FLAGS_ORIG}

	for name in Makefile.in protonfixes/Makefile; do
		file="$SOURCE_DIR/$name"
		[[ -e $file ]] || continue

		log "fixing up $name: ${CC_FLAGS_ORIG@Q}, ${RUST_FLAGS_ORIG@Q} -> ${CC_FLAGS@Q}, ${RUST_FLAGS@Q}"
		sed -r \
			-e "s|$CC_FLAGS_ORIG|$CC_FLAGS|" \
			-e "s|$RUST_FLAGS_ORIG|$RUST_FLAGS|" \
			-i "$file"
	done
fi

if grep -q 'enable-ccache' "$SOURCE_DIR/configure.sh"; then
	# legacy (ca. Proton-GE 8 and earlier)
	CMD+=( --enable-ccache )
fi

set -x

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
declare -p CMD
"$SOURCE_DIR/configure.sh" "${CMD[@]}" "${ARGS[@]}"

export CARGO_HOME="$CARGO_HOME"

CCACHE_CONFIGPATH="$CCACHE_DIR/ccache.conf"
mkdir -p "$CCACHE_DIR"
cat >"$CCACHE_CONFIGPATH" <<EOF
cache_dir = $CCACHE_DIR
max_size = 100G
EOF

sed -r "/^ENABLE_CCACHE := 1/{
aexport CCACHE_BASEDIR := $BUILD_DIR
aexport CCACHE_CONFIGPATH := $CCACHE_CONFIGPATH
aexport CCACHE_DIR := $CCACHE_DIR
}" -i Makefile

# newer Makefiles do not use offline tarballs -- sunrise by hand
mkdir -p "$SOURCE_DIR/contrib"
cp -av \
	"$SCRIPT_DIR/contrib"/*.tar* \
	-t "$SOURCE_DIR/contrib"

make redist

# ditto
cp -avu \
	"$SOURCE_DIR/contrib"/*.tar* \
	-t "$SCRIPT_DIR/contrib"

r-put *.tar.* '/mnt/data/Files/shared/dist/misc/deck/proton'
