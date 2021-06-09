#!/bin/bash

. lib.sh || exit

calc() {
	bc <<< "$1"
}

echo -n "Enter coords (AA.Ad BB.Bm CC.Cs N/S AA.Ad BB.Bm CC.Cs W/E): "
read INPUT

if [[ $INPUT =~ ^(([0-9.]+)[d°])?\ *(([0-9.]+)[m\'])?\ *(([0-9.]+)[s\"])?\ *([NS])\ *(([0-9.]+)[d°])?\ *(([0-9.]+)[m\'])?\ *(([0-9.]+)[s\"])?\ *([WE])$ ]]; then
	LAT_DEG="${BASH_REMATCH[2]:-0}"
	LAT_MIN="${BASH_REMATCH[4]:-0}"
	LAT_SEC="${BASH_REMATCH[6]:-0}"
	LAT_SIGN="${BASH_REMATCH[7]}"

	LON_DEG="${BASH_REMATCH[9]:-0}"
	LON_MIN="${BASH_REMATCH[11]:-0}"
	LON_SEC="${BASH_REMATCH[13]:-0}"
	LON_SIGN="${BASH_REMATCH[14]}"

	echo "Lat: $LAT_DEG deg $LAT_MIN min $LAT_SEC sec $LAT_SIGN"
	echo "Lat: $LON_DEG deg $LON_MIN min $LON_SEC sec $LON_SIGN"
else
	die "Wrong input: $INPUT"
fi

LAT_WORK="$(calc "$LAT_DEG*3600 + $LAT_MIN*60 + $LAT_SEC")"
LON_WORK="$(calc "$LON_DEG*3600 + $LON_MIN*60 + $LON_SEC")"

dms() {
	printf "%d°%d'%.3f\"%s" \
		$(calc "scale=0; $1/3600") \
		$(calc "scale=0; ($1%3600)/60") \
		$(calc "scale=0; ($1%60)") \
		"$2"
}

dmm() {
	printf "%d°%.3f'%s" \
		$(calc "scale=0; $1/3600") \
		$(calc "scale=0; p=($1%3600); scale=10; p/60") \
		"$2"
}

ddd() {
	printf "%.3f°%s" \
		$(calc "scale=10; $1/3600") \
		"$2"
}

dddd() {
	printf "%.10f°%s" \
		$(calc "scale=10; $1/3600") \
		"$2"
}

airbus_lat() {
	printf "%02d%02.2f%s" \
		$(calc "scale=0; $1/3600") \
		$(calc "scale=0; p=($1%3600); scale=10; p/60") \
		"$2"
}

airbus_lon() {
	printf "%03d%02.2f%s" \
		$(calc "scale=0; $1/3600") \
		$(calc "scale=0; p=($1%3600); scale=10; p/60") \
		"$2"
}

echo "Lat/lon (DMS): $(dms "$LAT_WORK" "$LAT_SIGN") / $(dms "$LON_WORK" "$LON_SIGN")"
echo "Lat/lon (DM.M): $(dmm "$LAT_WORK" "$LAT_SIGN") / $(dmm "$LON_WORK" "$LON_SIGN")"
echo "Lat/lon (D.DD): $(ddd "$LAT_WORK" "$LAT_SIGN") / $(ddd "$LON_WORK" "$LON_SIGN")"

echo "Lat/lon (D.DDDDDDD): $(dddd "$LAT_WORK" "$LAT_SIGN") / $(dddd "$LON_WORK" "$LON_SIGN")"

echo "Lat/lon (Airbus): $(airbus_lat "$LAT_WORK" "$LAT_SIGN")/$(airbus_lon "$LON_WORK" "$LON_SIGN")"
