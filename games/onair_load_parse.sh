#!/bin/bash

. lib.sh || exit

usage() {
	cat <<EOF
Usage: $0 <registration>
EOF
	exit 1
}

calc() {
	bc <<< "$1"
}

parse_weight() {
	declare -n in="$1" out="$2"
	local unit_in="$3" unit_out="$4"

	local work="$(tr -d -c "[0-9a-zA-Z]" <<< "$in")"

	# set default unit
	if [[ $work =~ ^[0-9]+$ ]]; then
		work="$work$unit_in"
	fi

	# special case gallons of jet fuel (as understood by OnAir)
	if [[ $work =~ ^([0-9]+)gal$ ]]; then
		work="$(calc "${work%gal} * 6.7")lbs"
	fi

	out="$(units --terse "$work" "$unit_out")"
	log "Converting $in (default unit $unit_in) = $out $unit_out"
}

onair_attendants() {
	local pax="$1"
	if (( pax >= 13 )); then
		echo "$((1 + (pax - 13) / 50 ))"
	else
		echo 0
	fi
}

#
# main
#

PAX_LBS=190

declare -A REGNR_TO_OEW_LBS
REGNR_TO_OEW_LBS=(
	[a319]=89999
	[a321xlr]=109746
)

declare -A REGNR_TO_XP_OEW_LBS
REGNR_TO_XP_OEW_LBS=(
	[a319]=89999
	[a321xlr]=105329
)

declare -A REGNR_TO_PILOTS
REGNR_TO_PILOTS=(
	[a319]=2
	[a321xlr]=2
)

if ! [[ $# == 1 ]]; then
	err "Expected 1 arguments, got $#: $*"
	usage
fi

regnr="$1"

if ! [[ ${REGNR_TO_OEW_LBS[$regnr]} ]]; then
	err "Bad registration: $regnr (possible: ${!REGNR_TO_OEW_LBS[*]})"
	usage
fi

print_hdr() {
	echo "---"
	echo
}

print_ftr() {
	echo
	echo "---"
}

print_xplane() {
	echo "X-Plane payload: $(calc "$PAX_LBS + $CARGO_LBS + $XP_OEW_DIFF_LBS") lbs"
	echo "X-Plane fuel: $FUEL_LBS lbs"
}

print_simbrief_in() {
	echo "SimBrief pax: $(( PAX_NR + CREW_NR ))"
	echo "SimBrief cargo: $(calc "scale=1; $CARGO_LBS / 1000")"
	echo "SimBrief ZFW (cross-check): $ZFW_LBS lbs"
}

print_simbrief_out() {
	echo "SimBrief TOW (cross-check): $TOW_LBS lbs"
}

print_onair() {
	echo "OnAir crew: $CREW_NR"
	echo "OnAir fuel: $ONAIR_FUEL_GAL gal ($FUEL_LBS lbs)"
}

print_toliss() {
	echo "ToLiss pax:   $TOLISS_PAX (220 lbs/pax)"
	#echo "ToLiss cargo: $CARGO_KG kg"
	#echo "ToLiss ZFW: $ZFW_KG kg"
	#echo "ToLiss fuel: $FUEL_KG kg"
	echo "ToLiss cargo: $CARGO_LBS lbs"
	echo "ToLiss ZFW:   $ZFW_LBS lbs"
	echo "ToLiss fuel:  $FUEL_LBS lbs"
}

print_acars() {
	echo "ACARS pax: $PAX_NR"
	echo "ACARS cargo: $CARGO_KG kg"
}

print_airbus_mcdu() {
	case "$1" in
	kg) declare -n ZFW=ZFW_KG; declare -n FUEL=FUEL_KG ;;
	lbs) declare -n ZFW=ZFW_LBS; declare -n FUEL=FUEL_LBS ;;
	*) die "print_airbus_mcdu: bad unit: $1" ;;
	esac

	MCDU_ZFW="$(calc "scale=1; $ZFW / 1000")"
	MCDU_FUEL="$(calc "scale=1; $FUEL / 1000")"
	
	case "$regnr" in
	a319)
		cat <<-EOF
		MCDU ZFWCG guidance:
		           empty           +0.0 in  28.6%
		           just pilots     -1.9 in  27.4%
		           full cargo      +3.3 in  30.6%
		           full cargo+pax  +2.5 in  30.1%

		EOF
	;;
	a321xlr)
		cat <<-EOF
		MCDU ZFWCG guidance:
		           empty           +0.0 in  28.6%
		           just pilots     -1.6 in  27.6%
		           full cargo      -4.1 in  26.1%
		           full cargo+pax  -2.9 in  26.8%
			   max zfw w/cg    +4.9 in  31.6%

		EOF
	;;
	*)
		cat <<-EOF
		MCDU ZFWCG guidance N/A

		EOF
	;;
	esac


	echo "MCDU ZFW: $MCDU_ZFW/xx.x (see above)"
	echo "MCDU block fuel: $MCDU_FUEL"
}

OEW_LBS="${REGNR_TO_OEW_LBS[$regnr]}"
XP_OEW_LBS="${REGNR_TO_XP_OEW_LBS[$regnr]}"
CREW_PILOTS="${REGNR_TO_PILOTS[$regnr]}"

XP_OEW_DIFF_LBS="$(calc "$OEW_LBS - $XP_OEW_LBS")"

echo -n "Enter ZFW (if known): "
read ZFW_LBS

if [[ "$ZFW_LBS" ]]; then
	PAX_NR=0
	CREW_FA=0
	CREW_NR="$CREW_PILOTS"
	PAX_LBS="$(calc "($CREW_NR + $PAX_NR) * 190")"

	CARGO_LBS="$(calc "$ZFW_LBS - $OEW_LBS - $PAX_LBS")"
else
	echo -n "Enter passenger count: "
	read PAX_NR

	CREW_FA="$(onair_attendants "$PAX_NR")"
	CREW_NR="$(( CREW_PILOTS + CREW_FA ))"
	PAX_LBS="$(calc "($CREW_NR + $PAX_NR) * 190")"

	echo -n "Enter cargo weight (lbs, or enter a unit): "
	read CARGO
	parse_weight CARGO CARGO_LBS lbs lbs

	ZFW_LBS="$(calc "$OEW_LBS + $PAX_LBS + $CARGO_LBS")"
fi

print_hdr
print_simbrief_in
print_ftr

echo -n "Enter fuel (lbs, or enter a unit): "
read FUEL
parse_weight FUEL FUEL_LBS lbs lbs

TOW_LBS="$(calc "$OEW_LBS + $PAX_LBS + $CARGO_LBS + $FUEL_LBS")"

ONAIR_FUEL_GAL="$(calc "$FUEL_LBS / 6.7")"

TOLISS_PAX="$(calc "($CREW_NR + $PAX_NR) * 190 / 220")"
CARGO_KG="$(units --terse "$CARGO_LBS lbs" "kg")"
FUEL_KG="$(units --terse "$FUEL_LBS lbs" "kg")"
ZFW_KG="$(units --terse "$ZFW_LBS lbs" "kg")"

print_hdr
print_xplane
echo
print_simbrief_in
print_simbrief_out
echo
print_onair
echo
print_toliss
echo
print_acars
echo
print_airbus_mcdu lbs
print_ftr
