#!/bin/sh

# Script to update Debian APT sources based on current version
# Inspects /etc/os-release for VERSION_CODENAME
# Finds Debian-related sources files, overwrites the first with appropriate config, removes others.
# Uses legacy .list or deb822 .sources format based on $1 or the first found file's extension.

set -e

usage() {
	cat >&2 <<-EOF
	Usage: $0 ["legacy"|"deb822"]
	EOF
	exit 1
}

# Parse arguments
arg_format=
if [ "$#" -gt 1 ]; then
	usage
elif [ "$#" -eq 1 ]; then
	case "$1" in
		legacy|deb822) arg_format="$1" ;;
		*)             usage ;;
	esac
fi

# Load os-release
if [ ! -f /etc/os-release ]; then
	echo "Error: /etc/os-release not found" >&2
	exit 1
fi
. /etc/os-release
codename="${VERSION_CODENAME:-}"

if [ -z "$codename" ]; then
	echo "Error: VERSION_CODENAME not found in /etc/os-release" >&2
	exit 1
fi

# Find all potential sources files
target_file=""
target_format=""
other_files=""
for file in \
	/etc/apt/sources.list \
	/etc/apt/sources.list.d/*.list \
	/etc/apt/sources.list.d/*.sources \
; do
	case "$file" in
		*.sources) file_format="deb822" ;;
		*.list)    file_format="legacy" ;;
		*)         echo "Internal error" >&2; exit 1 ;;
	esac

	if [ -f "$file" ] \
	&& [ -s "$file" ] \
	&& grep -q '\(deb\|archive\|security\)\.debian\.org' "$file"; then

		if [ -z "$target_file" ] \
		&& { [ -z "$arg_format" ] || [ "$file_format" = "$arg_format" ]; } \
		; then
			target_file="$file"
			target_format="$file_format"
		else
			other_files="$other_files $file"
		fi
	fi
done

if [ -z "$target_file" ] && [ -z "$other_files" ]; then
	echo "No Debian sources files found" >&2
	exit 1
elif [ -z "$target_file" ] && [ -n "$arg_format" ]; then
	# did not find a sources file with the specified format, use default location
	case "$arg_format" in
		deb822) target_file="/etc/apt/sources.list.d/debian.sources" ;;
		legacy) target_file="/etc/apt/sources.list" ;;
		*)      echo "Internal error" >&2; exit 1 ;;
	esac
	target_format="$arg_format"
elif [ -z "$target_file" ]; then
	# not possible
	echo "Internal error" >&2
	exit 1
fi

# Generate deb822 format sources content to stdout
make_deb822() {
	codename="$1"
	case "$codename" in
		stretch)
			cat <<-EOF
			Types: deb deb-src
			URIs: http://archive.debian.org/debian
			Suites: stretch stretch-proposed-updates
			Components: main contrib non-free
			Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

			Types: deb deb-src
			URIs: http://archive.debian.org/debian-security
			Suites: stretch/updates
			Components: main contrib non-free
			Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

			Types: deb deb-src
			URIs: http://archive.debian.org/debian
			Suites: stretch-backports
			Components: main contrib non-free
			Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

			Types: deb deb-src
			URIs: http://archive.debian.org/debian
			Suites: stretch-backports-sloppy
			Components: main contrib non-free
			Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
			EOF
			;;
		buster)
			cat <<-EOF
			Types: deb deb-src
			URIs: http://archive.debian.org/debian
			Suites: buster buster-updates buster-proposed-updates
			Components: main contrib non-free
			Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

			Types: deb deb-src
			URIs: http://archive.debian.org/debian-security
			Suites: buster/updates
			Components: main contrib non-free
			Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

			Types: deb deb-src
			URIs: http://archive.debian.org/debian
			Suites: buster-backports
			Components: main contrib non-free
			Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

			Types: deb deb-src
			URIs: http://archive.debian.org/debian
			Suites: buster-backports-sloppy
			Components: main contrib non-free
			Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
			EOF
			;;
		bullseye)
			cat <<-EOF
			Types: deb deb-src
			URIs: http://deb.debian.org/debian
			Suites: bullseye bullseye-updates bullseye-proposed-updates
			Components: main contrib non-free
			Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

			Types: deb deb-src
			URIs: http://security.debian.org/debian-security
			Suites: bullseye-security
			Components: main contrib non-free
			Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

			# Backports are archived
			Types: deb deb-src
			URIs: http://archive.debian.org/debian
			Suites: bullseye-backports
			Components: main contrib non-free
			Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

			Types: deb deb-src
			URIs: http://archive.debian.org/debian
			Suites: bullseye-backports-sloppy
			Components: main contrib non-free
			Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
			EOF
			;;
		bookworm)
			cat <<-EOF
			Types: deb deb-src
			URIs: http://deb.debian.org/debian
			Suites: bookworm bookworm-updates bookworm-proposed-updates
			Components: main contrib non-free non-free-firmware
			Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

			Types: deb deb-src
			URIs: http://security.debian.org/debian-security
			Suites: bookworm-security
			Components: main contrib non-free non-free-firmware
			Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

			Types: deb deb-src
			URIs: http://deb.debian.org/debian
			Suites: bookworm-backports
			Components: main contrib non-free non-free-firmware
			Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

			Types: deb deb-src
			URIs: http://deb.debian.org/debian
			Suites: bookworm-backports-sloppy
			Components: main contrib non-free non-free-firmware
			Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
			EOF
			;;
		trixie)
			cat <<-EOF
			Types: deb deb-src
			URIs: http://deb.debian.org/debian
			Suites: trixie trixie-updates trixie-proposed-updates
			Components: main contrib non-free non-free-firmware
			Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

			Types: deb deb-src
			URIs: http://security.debian.org/debian-security
			Suites: trixie-security
			Components: main contrib non-free non-free-firmware
			Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

			Types: deb deb-src
			URIs: http://deb.debian.org/debian
			Suites: trixie-backports
			Components: main contrib non-free non-free-firmware
			Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
			EOF
			;;
		sid)
			cat <<-EOF
			Types: deb deb-src
			URIs: http://deb.debian.org/debian
			Suites: sid
			Components: main contrib non-free non-free-firmware
			Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
			EOF
			;;
		*)
			echo "Unsupported codename: $codename" >&2
			exit 1
			;;
	esac
}

# Generate legacy format sources content to stdout
make_legacy() {
	codename="$1"
	case "$codename" in
		stretch)
			cat <<-EOF
			deb http://archive.debian.org/debian/ stretch main contrib non-free
			deb-src http://archive.debian.org/debian/ stretch main contrib non-free

			deb http://archive.debian.org/debian-security/ stretch/updates main contrib non-free
			deb-src http://archive.debian.org/debian-security/ stretch/updates main contrib non-free

			deb http://archive.debian.org/debian/ stretch-proposed-updates main contrib non-free
			deb-src http://archive.debian.org/debian/ stretch-proposed-updates main contrib non-free

			deb http://archive.debian.org/debian/ stretch-backports main contrib non-free
			deb-src http://archive.debian.org/debian/ stretch-backports main contrib non-free

			deb http://archive.debian.org/debian/ stretch-backports-sloppy main contrib non-free
			deb-src http://archive.debian.org/debian/ stretch-backports-sloppy main contrib non-free
			EOF
			;;
		buster)
			cat <<-EOF
			deb http://archive.debian.org/debian/ buster main contrib non-free
			deb-src http://archive.debian.org/debian/ buster main contrib non-free

			deb http://archive.debian.org/debian-security/ buster/updates main contrib non-free
			deb-src http://archive.debian.org/debian-security/ buster/updates main contrib non-free

			deb http://archive.debian.org/debian/ buster-updates main contrib non-free
			deb-src http://archive.debian.org/debian/ buster-updates main contrib non-free

			deb http://archive.debian.org/debian/ buster-proposed-updates main contrib non-free
			deb-src http://archive.debian.org/debian/ buster-proposed-updates main contrib non-free

			deb http://archive.debian.org/debian/ buster-backports main contrib non-free
			deb-src http://archive.debian.org/debian/ buster-backports main contrib non-free

			deb http://archive.debian.org/debian/ buster-backports-sloppy main contrib non-free
			deb-src http://archive.debian.org/debian/ buster-backports-sloppy main contrib non-free
			EOF
			;;
		bullseye)
			cat <<-EOF
			deb http://deb.debian.org/debian/ bullseye main contrib non-free
			deb-src http://deb.debian.org/debian/ bullseye main contrib non-free

			deb http://security.debian.org/debian-security bullseye-security main contrib non-free
			deb-src http://security.debian.org/debian-security bullseye-security main contrib non-free

			deb http://deb.debian.org/debian/ bullseye-updates main contrib non-free
			deb-src http://deb.debian.org/debian/ bullseye-updates main contrib non-free

			deb http://deb.debian.org/debian/ bullseye-proposed-updates main contrib non-free
			deb-src http://deb.debian.org/debian/ bullseye-proposed-updates main contrib non-free

			# Backports are archived
			deb http://archive.debian.org/debian/ bullseye-backports main contrib non-free
			deb-src http://archive.debian.org/debian/ bullseye-backports main contrib non-free

			deb http://archive.debian.org/debian/ bullseye-backports-sloppy main contrib non-free
			deb-src http://archive.debian.org/debian/ bullseye-backports-sloppy main contrib non-free
			EOF
			;;
		bookworm)
			cat <<-EOF
			deb http://deb.debian.org/debian/ bookworm main contrib non-free non-free-firmware
			deb-src http://deb.debian.org/debian/ bookworm main contrib non-free non-free-firmware

			deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
			deb-src http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware

			deb http://deb.debian.org/debian/ bookworm-updates main contrib non-free non-free-firmware
			deb-src http://deb.debian.org/debian/ bookworm-updates main contrib non-free non-free-firmware

			deb http://deb.debian.org/debian/ bookworm-proposed-updates main contrib non-free non-free-firmware
			deb-src http://deb.debian.org/debian/ bookworm-proposed-updates main contrib non-free non-free-firmware

			deb http://deb.debian.org/debian/ bookworm-backports main contrib non-free non-free-firmware
			deb-src http://deb.debian.org/debian/ bookworm-backports main contrib non-free non-free-firmware

			deb http://deb.debian.org/debian/ bookworm-backports-sloppy main contrib non-free non-free-firmware
			deb-src http://deb.debian.org/debian/ bookworm-backports-sloppy main contrib non-free non-free-firmware
			EOF
			;;
		trixie)
			cat <<-EOF
			deb http://deb.debian.org/debian/ trixie main contrib non-free non-free-firmware
			deb-src http://deb.debian.org/debian/ trixie main contrib non-free non-free-firmware

			deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
			deb-src http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware

			deb http://deb.debian.org/debian/ trixie-updates main contrib non-free non-free-firmware
			deb-src http://deb.debian.org/debian/ trixie-updates main contrib non-free non-free-firmware

			deb http://deb.debian.org/debian/ trixie-proposed-updates main contrib non-free non-free-firmware
			deb-src http://deb.debian.org/debian/ trixie-proposed-updates main contrib non-free non-free-firmware

			deb http://deb.debian.org/debian/ trixie-backports main contrib non-free non-free-firmware
			deb-src http://deb.debian.org/debian/ trixie-backports main contrib non-free non-free-firmware
			EOF
			;;
		sid)
			cat <<-EOF
			deb http://deb.debian.org/debian/ sid main contrib non-free non-free-firmware
			deb-src http://deb.debian.org/debian/ sid main contrib non-free non-free-firmware
			EOF
			;;
		*)
			echo "Unsupported codename: $codename" >&2
			exit 1
			;;
	esac
}

# Write content based on codename and format
if [ "$target_format" = "deb822" ]; then
	make_deb822 "$codename" >"$target_file"
else
	make_legacy "$codename" >"$target_file"
fi
# Remove other sources files, if any
if [ -n "$other_files" ]; then
	rm -vf $other_files
fi

echo "Wrote sources to $target_file."
if [ -n "$other_files" ]; then
	echo "Removed $(echo "$other_files" | wc -w) other sources files."
fi
