#!/bin/bash -e

. lib.sh

_usage() {
	cat <<EOF
Usage: $0 <Key-ID> <output file>
EOF
}
(( $# == 2 )) || usage "Expected 2 parameters, got $#"

KEY_ID="$1"
EXPORT_FILE="$2"

read -p "Key passphrase: " -s KEY_PASSPHRASE; echo
read -p "Export passphrase: " -s EXPORT_PASSPHRASE; echo

KEY_FILE="$(mktemp)"
EXPORT_GNUPGHOME="$(mktemp -d)"
cleanup() {
	if [[ "$EXPORT_GNUPGHOME" ]]; then
		GNUPGHOME="$EXPORT_GNUPGHOME" gpgconf --kill all
		rm -rf "$EXPORT_GNUPGHOME"
	fi
	if [[ "$KEY_FILE" ]]; then
		rm -rf "$KEY_FILE"
	fi
}
trap cleanup EXIT

do_gpg() {
	gpg --pinentry-mode loopback "$@"
}

do_gpg --passphrase-fd 0 --export-secret-keys --export-options backup "$KEY_ID" >"$KEY_FILE" <<<"$KEY_PASSPHRASE"

GNUPGHOME="$EXPORT_GNUPGHOME" do_gpg --passphrase-fd 0 --import "$KEY_FILE" <<<"$KEY_PASSPHRASE"
GNUPGHOME="$EXPORT_GNUPGHOME" do_gpg --command-fd 0 --change-passphrase "$KEY_ID" <<EOF
$KEY_PASSPHRASE
$EXPORT_PASSPHRASE
EOF
GNUPGHOME="$EXPORT_GNUPGHOME" do_gpg --passphrase-fd 0 --export-secret-keys --armor "$KEY_ID" >"$EXPORT_FILE" <<<"$EXPORT_PASSPHRASE"
GNUPGHOME="$EXPORT_GNUPGHOME" do_gpg --passphrase-fd 0 --export --armor "$KEY_ID" >"$EXPORT_FILE.pub" <<<"$EXPORT_PASSPHRASE"
