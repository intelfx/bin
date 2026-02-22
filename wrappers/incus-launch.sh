#!/bin/bash

set -eo pipefail
shopt -s lastpipe
shopt -s extglob

# shellcheck source=../lib/lib.sh
. lib.sh

#
# incus-launch.sh: (multi-)distro-specific wrapper for running OCI containers
# of different distributions in Incus.
# This is a unified rewrite of `wrappers/podman-{arch,deb,rh}`.
#

do_incus() {
	local -
	set -x
	incus "${GLOBAL_ARGS[@]}" "$@"
}

exec_incus() {
	local -
	set -x
	exec incus "${GLOBAL_ARGS[@]}" "$@"
}

incus_add_disk() {
	local arg="$1" args=("${@:2}") name src dest opts

	IFS=: read -r src dest opts <<<"$arg"
	IFS=, read -ra opts <<<"$opts"

	[[ $dest ]] || dest="$src"
	# escape destination path to use as the volume name
	# do not use systemd-escape as it escapes special characters as \x sequences which are reversible but illegal in Incus
	# we don't need a reversible encoding so just use tr to squash all illegal characters into dashes
	# name="$(systemd-escape --path "$dest" | tr -cd 'A-Za-z0-9/-:_.')"
	name="$(echo -n "${dest#/}" | tr -cs '[:alnum:]:_.-' '-')"
	# translate some Docker/Podman-style options to Incus properties
	if in_array ro "${opts[@]}"; then
		args+=("readonly=true")
	fi

	do_incus \
		profile device add "$PROFILE" "$name" disk \
		source="$src" \
		path="$dest" \
		shift=true \
		"${args[@]}"
}

incus_define_arch() {
	# primary pacman cache (rw)
	incus_add_disk /var/cache/pacman/pkg
	# fake pacman cache for local repo (ro)
	incus_add_disk /var/cache/pacman/repo::ro
	# local repo (ro)
	incus_add_disk /srv/repo::ro

	# pacman configuration, mirrorlist and keyring (ro)
	# TODO: when pacman gains support for configuration dropins
	#       (e.g. /etc/pacman.conf.d), migrate to that
	local pacman_conf
	if [[ $PROFILE == oci-* ]]
	then pacman_conf="$HOME/bin/etc/pacman-oci.conf"
	else pacman_conf="$HOME/bin/etc/pacman.conf"
	fi
	incus_add_disk "$pacman_conf:/etc/pacman.conf":ro
	incus_add_disk /etc/pacman.d/mirrorlist::ro
	incus_add_disk /etc/pacman.d/gnupg::ro
}

incus_define() {
	local PROFILE="$1"

	if do_incus profile list -c n -f csv,noheader "$PROFILE" | grep -Fx "$PROFILE"; then
		return
	fi

	do_incus \
		profile create "$PROFILE"

	case "$PROFILE" in
	?(oci-)arch) incus_define_arch "$@" ;;
	?(oci-)@(deb|rh)) die "Unimplemented: ${PROFILE@Q}" ;;
	*) die "Unknown profile: ${PROFILE@Q}" ;;
	esac

	# Developer toolchains and caches – rw
	incus_add_disk "$HOME/.cargo:/root/.cargo"
	incus_add_disk "$HOME/go:/root/go"
	incus_add_disk "$HOME/.cache/cargo:/root/.cache/cargo"
	incus_add_disk "$HOME/.cache/go-mod:/root/.cache/go-mod"
	incus_add_disk "$HOME/.cache/go-build:/root/.cache/go-build"

	do_incus \
		profile set "$PROFILE" \
		boot.autostart=false \
		security.nesting=true \
		environment.GOMODCACHE=/root/.cache/go-mod \
		environment.GOCACHE=/root/.cache/go-build \
		environment.GOPATH=/root/go \
		# EOL
}

incus_launch() {
	local PROFILE="$1" CMD="$2"
	shift 2

	local -a args
	args+=(
		# Incus profiles cannot be inherited and `default` is not implied,
		# but we can specify multiple profiles at the same time -- do that
		--profile default
		--profile "$PROFILE"
	)

	local env
	for env in \
		CC CXX \
		CFLAGS CXXFLAGS LDFLAGS \
		RUSTFLAGS "${!CARGO_@}" \
		GOFLAGS "${!CGO_@}" \
	; do
		args+=(--config "environment.${env}=${!env}")
	done

	exec_incus \
		"$CMD" \
		"${args[@]}" \
		"$@"
}

ORIG_ARGS=( "$@" )
GLOBAL_ARGS=()
PROFILE_IS_OCI=
PROFILE=
CMD=

# multi-call support
case "${LIB_ARGV0##*/}" in
	incus-arch) PROFILE="oci-arch" ;;
	incus-deb) PROFILE="oci-deb" ;;
	incus-rh) PROFILE="oci-rh" ;;
esac

while (( $# )); do
	case "$1" in
	create|\
	launch)     CMD="$1"; shift; break ;;

	--oci)      PROFILE_IS_OCI=1; shift ;;

	--oci-arch) PROFILE_IS_OCI=1 ;&
	--arch)     PROFILE="${PROFILE_IS_OCI:+oci-}arch"; shift ;;
	--oci-deb)  PROFILE_IS_OCI=1 ;&
	--deb)      PROFILE="${PROFILE_IS_OCI:+oci-}deb"; shift ;;
	--oci-rh)   PROFILE_IS_OCI=1 ;&
	--rh)       PROFILE="${PROFILE_IS_OCI:+oci-}rh"; shift ;;

	*)          GLOBAL_ARGS+=("$1"); shift ;;
	esac
done

if ! [[ $PROFILE && $CMD ]]; then
	set -x
	exec incus "${ORIG_ARGS[@]}"
fi

incus_define "$PROFILE"
incus_launch "$PROFILE" "$CMD" "$@"
