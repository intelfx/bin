#!/bin/sh

OPKG_STATUS="${1:-/usr/lib/opkg/status}"

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

BEGIN { FS = ": "; print $foo }
/^Package: / { pkg_new($2) }
/^Status: .*\<user\>.*/ { p_user = 1; pkg_check() }
'

function awk_opkg_status() {
	awk "$@" "$OPKG_STATUS"
}

awk_opkg_status "$AWK_FILTER_PACKAGES" | sort
