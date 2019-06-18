#!/bin/sh

OPKG_STATUS="${1:-/usr/lib/opkg/status}"

function awk_opkg_status() {
	awk "$@" "$OPKG_STATUS"
}

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
	p_time = 0
}

function pkg_check()
{
	if (p_user && p_time) {
		print package
	}
}

BEGIN { FS = ": " }
/^Package: / { pkg_new($2) }
/^Status: .*\<user\>.*/ { p_user = 1; pkg_check() }
/^Installed-Time: / { if ($2 > min_time) { p_time = 1; pkg_check() } }
'

MIN_TIME="$(awk_opkg_status "$AWK_FIND_MIN_TIME")"
awk_opkg_status -v min_time="$MIN_TIME" "$AWK_FILTER_PACKAGES" | sort
