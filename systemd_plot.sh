#!/bin/bash
FILE="$HOME/tmp/boot.svg"
systemd-analyze plot > $FILE
rekonq $FILE
