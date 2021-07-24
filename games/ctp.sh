#!/bin/bash

set -eo pipefail
shopt -s lastpipe

log() {
	echo ":: $*" >&2
}

err() {
	echo "E: $*" >&2
}

die() {
	err "$@"
	exit 1
}

DELAY=15
while :; do
	curl -fsSL 'https://ctp.vatsim.net/api/search/bookings?departure=99&arrival=11' -H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:85.0) Gecko/20100101 Firefox/85.0' -H 'Accept: application/json, text/plain, */*' -H 'Accept-Language: ru-RU,ru;q=0.8,en-US;q=0.5,en;q=0.3' --compressed -H 'X-Requested-With: XMLHttpRequest' -H 'X-Socket-Id: 924391725.542360590' -H 'DNT: 1' -H 'Connection: keep-alive' -H 'Referer: https://ctp.vatsim.net/bookings' -H 'TE: Trailers' -b cookiejar -c cookiejar -o resp && rc=2 || rc=$?

	if (( rc == 0 )); then
		if [[ "$(<resp)" == "[]" ]]; then
			log "No luck, sleeping"
		else
			length="$(jq -r "length" resp)"
			echo >&2
			log "====== DING DONG, $length slots ======"
			#jq resp
			for (( i=0; i<DELAY; ++i )); do
				echo -n $'\a'
				sleep 1
			done
			continue
		fi
	else
		err "curl returned an error: $rc"
		cat resp >&2
	fi
	sleep $DELAY
done
