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

declare -A CC_FLAGS_DEVICES=(
	[native]="-march=native"
	[deck]="-march=znver2 --param=l1-cache-line-size=64 --param=l1-cache-size=32 --param=l2-cache-size=512"
	[mtl8]="-march=skylake -mtune=generic -mabm -mavx256-split-unaligned-load -mavx256-split-unaligned-store -mclwb -mgfni -mmovdir64b -mmovdiri -mno-sgx -mpconfig -mpku -mptwrite -mrdpid -msha -mshstk -mvaes -mvpclmulqdq -mwaitpkg --param=l1-cache-line-size=64 --param=l1-cache-size=32 --param=l2-cache-size=24576"  # gcc 10
	[mtl]="-march=meteorlake -mabm -mno-cldemote -mno-kl -mno-sgx -mno-widekl -mshstk --param=l1-cache-line-size=64 --param=l1-cache-size=48 --param=l2-cache-size=24576"  # gcc 14
	#[mtl]="-march=meteorlake -mabm -mno-kl -mno-sgx -mno-widekl -mshstk --param=l1-cache-line-size=64 --param=l1-cache-size=48 --param=l2-cache-size=24576"  # gcc 15
)
declare -A RUST_FLAGS_DEVICES=(
	[native]="-Ctarget-cpu=native"
	[deck]="-Ctarget-cpu=znver2"
	[mtl8]="-Ctarget-cpu=alderlake" # rustc 1.68 / LLVM 15
	[mtl]="-Ctarget-cpu=alderlake" # rustc 1.68 / LLVM 15
	#[mtl]="-Ctarget-cpu=meteorlake"
)
_devices=( "${!CC_FLAGS_DEVICES[@]}" )

CMD=()
ARGS=()
unset TAG
unset PATCH_VERSION
unset ARG_TAG
unset ARG_PATCH_VERSION
unset ARG_MARCH
unset ARG_CFLAGS
unset ARG_RUSTFLAGS
unset ARG_DEVICE
unset CC_FLAGS
unset RUST_FLAGS

_usage() {
	cat <<EOF
Usage: $0 [--build-tag SUFFIX] [--march MARCH] [--cflags FLAGS] [--rustflags FLAGS] [--device DEVICE] [-v PATCH-VERSION]

--build-tag SUFFIX	append -SUFFIX to the name of the build
--march MARCH		replace ${MARCH_ORIG@Q} in ${CC_FLAGS_ORIG@Q} and ${RUST_FLAGS_ORIG@Q} with given string
--cflags FLAGS		replace entire ${CC_FLAGS_ORIG@Q} with given string
--rustflags FLAGS	replace entire ${RUST_FLAGS_ORIG@Q} with given string
--device DEVICE		replace entire flags (see above) with flags for given device (options: $(join ', ' "${_devices[@]@Q}"))
-v PATCH-VERSION	use given patchset instead of autodetected (7ge, 8ge, 9ge, 10ge, ...)
EOF
}

while (( $# )); do
	declare k v n
	if get_arg k v n --build-tag -- "$@"; then
		ARG_TAG="$v"
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
	elif get_arg k v n --device -- "$@"; then
		ARG_DEVICE="$v"
		shift "$n"
	elif get_arg k v n -v -- "$@"; then
		ARG_PATCH_VERSION="$v"
		shift "$n"
	elif get_flag k n -h --help -- "$@"; then
		usage
		exit
	else
		ARGS+=( "$1" )
		shift 1
	fi
done

if [[ ${ARG_TAG+set} ]]; then
	TAG="$ARG_TAG"
elif [[ ${ARG_DEVICE+set} ]]; then
	TAG="$ARG_DEVICE"
fi

SOURCE_TAG="$(cd "$SOURCE_DIR" && git describe --tags --abbrev=0)"

if [[ ${TAG+set} ]]; then
	BUILD_NAME="$SOURCE_TAG-$TAG"
else
	BUILD_NAME="$SOURCE_TAG"
fi

if [[ ${ARG_PATCH_VERSION+set} ]]; then
	PATCH_VERSION="$ARG_PATCH_VERSION"
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
fi

PATCH_DIR="$SCRIPT_DIR/patches-${PATCH_VERSION}"
if ! [[ -d "$PATCH_DIR" ]]; then
	die "Patch directory does not exist: $PATCH_DIR"
fi

if [[ $ARG_MARCH ]]; then
	CC_FLAGS="${CC_FLAGS_ORIG/$MARCH_ORIG/$ARG_MARCH}"
	RUST_FLAGS="${RUST_FLAGS_ORIG/$MARCH_ORIG/$ARG_MARCH}"
fi
if [[ $ARG_DEVICE ]]; then
	CC_FLAGS="${CC_FLAGS_DEVICES[$ARG_DEVICE]}"
	RUST_FLAGS="${RUST_FLAGS_DEVICES[$ARG_DEVICE]}"
	if ! [[ $CC_FLAGS && $RUST_FLAGS ]]; then
		usage "Invalid --device= value: ${ARG_DEVICE@Q}"
	fi

fi
if [[ $ARG_CFLAGS ]]; then
	CC_FLAGS="$ARG_CFLAGS"
fi
if [[ $ARG_RUSTFLAGS ]]; then
	RUST_FLAGS="$ARG_RUSTFLAGS"
fi

print_header() {
	log "Build name suffix:               $(ifelse "$TAG" "$(ifelse "$ARG_TAG" "-$TAG" "-$TAG (default)")" "(unset)")"
	log "Source tag:                      ${SOURCE_TAG@Q}"
	log "Build name:                      ${BUILD_NAME@Q}"
	log "Patches:                         $(ifelse "$ARG_PATCH_VERSION" "${PATCH_VERSION@Q}" "${PATCH_VERSION@Q} (default)")"
	log "-march:                          $(ifelse "$ARG_MARCH" "${ARG_MARCH@Q}" "(unset)")"
	log "Device:                          $(ifelse "$ARG_DEVICE" "${ARG_DEVICE@Q}" "(unset)")"
	log "CFLAGS:                          $(ifelse "$CC_FLAGS" "(unset)")"
	log "RUSTFLAGS:                       $(ifelse "$RUST_FLAGS" "(unset)")"
	log "./configure args:                ${CMD[*]@Q}"
}


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

CMD=(
	--container-engine=podman
	--build-name="$BUILD_NAME"
)

if grep -q 'enable-ccache' "$SOURCE_DIR/configure.sh"; then
	# legacy (ca. Proton-GE 8 and earlier)
	CMD+=( --enable-ccache )
fi

print_header

set -x

mkdir -p "$BUILD_DIR"
find "$BUILD_DIR" -mindepth 1 -maxdepth 1 -execdir rm -rf {} \+
cd "$BUILD_DIR"
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
mkdir -p "$SCRIPT_DIR/contrib" "$SOURCE_DIR/contrib"
cp -av \
	"$SCRIPT_DIR/contrib" \
	-T "$SOURCE_DIR/contrib"

make redist

# ditto
cp -avu \
	"$SOURCE_DIR/contrib" \
	-T "$SCRIPT_DIR/contrib"

r-put *.tar.* '/mnt/data/Files/shared/dist/misc/deck/proton'
