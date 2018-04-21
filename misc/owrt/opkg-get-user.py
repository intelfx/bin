#!/usr/bin/env python3

import sys
from lib import opkg

if len(sys.argv) > 1:
	parsed = opkg.Db(sys.argv[1])
else:
	parsed = opkg.Db()

min_time = min([
	pkg['Installed-Time']
	for pkg
	in parsed.db
])

user_pkgs = [
	pkg
	for pkg
	in parsed.db
	if pkg['Installed-Time'] > min_time and 'user' in pkg['Status']
]

print('\n'.join([ pkg['Package'] for pkg in user_pkgs ]))
