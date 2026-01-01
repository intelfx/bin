#!/usr/bin/env bash

set -eo pipefail

# fetch status
STATUS=$(vcgencmd get_throttled | cut -d "=" -f 2)

# decode - https://www.raspberrypi.com/documentation/computers/os.html#get_throttled
echo "vcgencmd get_throttled ($STATUS)"
IFS=","
for BITMAP in \
   00,"currently under-voltage" \
   01,"ARM frequency currently capped" \
   02,"currently throttled" \
   03,"soft temperature limit reached" \
   16,"under-voltage has occurred since last reboot" \
   17,"ARM frequency capping has occurred since last reboot" \
   18,"throttling has occurred since last reboot" \
   19,"soft temperature reached since last reboot"
do set -- $BITMAP
   if [ $(($STATUS & 1 << $1)) -ne 0 ] ; then echo "  - $2" ; fi
done

echo "vcgencmd measure_volts:"
for S in core sdram_c sdram_i sdram_p ; do printf '%9s %s\n' "$S" "$(vcgencmd measure_volts $S)" ; done

echo "Temperature: $(vcgencmd measure_temp)"
