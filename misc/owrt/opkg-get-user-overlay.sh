#!/bin/sh

OPKG_STATUS="usr/lib/opkg/status"

if [ "$#" -eq 2 ]; then
	OPKG_STATUS_ROM="$1"
	OPKG_STATUS_OVL="$2"
elif [ "$#" -eq 1 ]; then
	OPKG_STATUS_ROM="/rom/$1"
	OPKG_STATUS_OVL="/$1"
else
	OPKG_STATUS_ROM="/rom/$OPKG_STATUS"
	OPKG_STATUS_OVL="/$OPKG_STATUS"
fi

AWK_FIND_MIN_TIME='
BEGIN { min = systime(); FS = ": " }
/^Installed-Time: / { min = min < $2 ? min : $2 }
END { print min }
'

AWK_FILTER_PACKAGES='
function pkg_new(pkg)
{
	package = pkg
	p_user = 0
}

function pkg_check()
{
	if (p_user) {
		print package
	}
}

BEGIN { FS = ": " }
/^Package: / { pkg_new($2) }
/^Status: .*\<user\>.*/ { p_user = 1; pkg_check() }
'

function awk_opkg_status() {
	awk "$@" "$OPKG_STATUS"
}

function cleanup() {
	rm -f "$PKGS_IN_ROM" "$PKGS_IN_OVERLAY"
}
trap cleanup EXIT

PKGS_IN_ROM="$(mktemp)"
PKGS_IN_OVERLAY="$(mktemp)"

awk "$AWK_FILTER_PACKAGES" $OPKG_STATUS_ROM | sort > "$PKGS_IN_ROM"
awk "$AWK_FILTER_PACKAGES" $OPKG_STATUS_OVL | sort > "$PKGS_IN_OVERLAY"

# comm -12
cat "$PKGS_IN_ROM" "$PKGS_IN_OVERLAY" | sort | uniq -u
