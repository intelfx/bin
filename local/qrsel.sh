#!/bin/bash

set -e

FILE="/tmp/qrencode-$$.png"
trap "rm -f '$FILE'" EXIT ERR

xsel -b | qrencode -t PNG -o "$FILE"
exec xdg-open "$FILE"
