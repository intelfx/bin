#!/bin/bash

. lib.sh || exit 1

while (( $# )); do
	case "$1" in
	in|was|has|present)
		FUEL_IN="$2"
		shift 2
		;;
	out|need|desired|required)
		FUEL_OUT="$2"
		shift 2
		;;
	density)
		FUEL_DENSITY="$2"
		shift 2
		;;
	units)
		FUEL_VOLUME_UNITS="$2"
		shift 2
		;;
	*)
		die "Bad argument: $1"
		;;
	esac
done

if ! [[ "$FUEL_IN" ]]; then
	die "Fuel in not set"
fi

parse_units() {
	local in="$1"
	local name="$2"
	local default_units="$3"

	[[ "$in" ]] || die "$name not set"

	if [[ "$in" =~ ^([0-9.]+)\ *([a-z/()]+)$ ]]; then
		echo "${BASH_REMATCH[1]} (${BASH_REMATCH[2]})"
	elif [[ "$in" =~ ^[0-9.]+$ ]]; then
		if [[ "$default_units" == "<density>" ]]; then
			if (( $(<<<"$in >= 5" bc -l) )); then
				default_units="lbs/gal"
			elif (( $(<<<"$in <= 1" bc -l) )); then
				default_units="kg/liter"
			else
				die "Could not guess fuel density unit, unusual fuel density value: $in"
			fi
		fi

		log "$name: assuming $in $default_units"
		echo "$in ($default_units)"
	else
		die "$name: bad value: $in"
	fi
}

extract_units() {

	if [[ "$1" =~ ^([0-9.]+)\ *([a-z/()]+)$ ]]; then
		echo "${BASH_REMATCH[2]}"
	else
		die "$2: bad value: $1"
	fi
}

round_up_to() {
	bc -l <<< "scale=0; ($1 + $2 - 0.01) / $2 * $2"
}

round_down_to() {
	bc -l <<< "scale=0; $1 / $2 * $2"
}

FUEL_IN="$(parse_units "$FUEL_IN" "Fuel present" "lbs")"
FUEL_OUT="$(parse_units "$FUEL_OUT" "Fuel required" "lbs")"
FUEL_DENSITY="$(parse_units "$FUEL_DENSITY" "Fuel density" "<density>")"
FUEL_DENSITY_UNITS="${FUEL_DENSITY##* }"

if ! [[ "$FUEL_VOLUME_UNITS" ]]; then
	case "$FUEL_DENSITY_UNITS" in
	*gal*)
		FUEL_VOLUME_UNITS=gal
		;;
	*liter*)
		FUEL_VOLUME_UNITS=liter
		;;
	*)
		die "Could not infer fuel volume unit, unusual fuel density unit: $FUEL_DENSITY_UNIT"
		;;
	esac
fi

FUEL_MASS_UNITS="lbs"

FUEL_VOLUME="$(units -t "($FUEL_OUT - $FUEL_IN) / $FUEL_DENSITY" "$FUEL_VOLUME_UNITS")"
case "$FUEL_VOLUME_UNITS" in
gal)
	FUEL_VOLUME="$(round_up_to "$FUEL_VOLUME" 10)"
	;;
liter)
	FUEL_VOLUME="$(round_up_to "$FUEL_VOLUME" 40)"
	;;
esac

FUEL_OUT_ACTUAL="$(units -t "$FUEL_IN + $FUEL_VOLUME $FUEL_VOLUME_UNITS * $FUEL_DENSITY" "$FUEL_MASS_UNITS")"
FUEL_OUT_ACTUAL="$(round_down_to "$FUEL_OUT_ACTUAL" 10)"

echo "Request volume: $FUEL_VOLUME $FUEL_VOLUME_UNITS"
echo "Final mass:     $FUEL_OUT_ACTUAL $FUEL_MASS_UNITS"
