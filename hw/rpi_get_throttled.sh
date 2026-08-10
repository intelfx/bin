#!/bin/bash

set -eo pipefail
shopt -s lastpipe
shopt -s extglob

# we both parse and print floating-point numbers, and we measure box-drawing
# characters with ${#var}
export LC_ALL=C.UTF-8

# shellcheck source=../lib/lib.sh
. lib.sh

#
# defaults
#

BOX_WIDTH=72
# the widest layout below (L_THROTTLE_CHIPS) does not fit into anything narrower
BOX_WIDTH_MIN=66
BOX_CHARSET=unicode
COLOR=0

_usage() {
	cat <<EOF
Usage: ${0##*/} [OPTIONS]

Display Raspberry Pi throttling state, temperatures, clocks, voltages, and PMIC
per-rail power, decoded from vcgencmd(1) and sysfs.

Options:
	-c, --clocks		Report all clock domains, not just ARM
	-P, --no-power		Do not read the PMIC ADCs (Pi 5 only)
	-t, --throttling=STYLE	Throttling display style, 1-3 or "all" (def.: 1)
					1: one-line summary
					2: two-line display
					3: list of reasons
	-w, --width=N		Block width, in characters
				(default: $BOX_WIDTH, minimum: $BOX_WIDTH_MIN)
	    --ascii		Draw blocks with ASCII instead of Unicode
	    --color=WHEN	Colorize output: always, auto or never
				(default: auto; honors \$TERM and \$NO_COLOR)
EOF
}


#
# ANSI SGR (Solarized palette)
#

declare -A SGR_COLORS=(
	[base03]=002b36  [base02]=073642  [base01]=586e75  [base00]=657b83
	[base0]=839496   [base1]=93a1a1   [base2]=eee8d5   [base3]=fdf6e3
	[yellow]=b58900  [orange]=cb4b16  [red]=dc322f     [magenta]=d33682
	[violet]=6c71c4  [blue]=268bd2    [cyan]=2aa198    [green]=859900
)

declare -A SGR_ATTRS=(
	[reset]=0  [bold]=1   [dim]=2     [italic]=3
	[under]=4  [blink]=5  [invert]=7  [strike]=9
)

# sgr <ATTR...>: build an SGR escape sequence.
# ATTR is either "fg=COLOR"/"bg=COLOR" (see $SGR_COLORS) or an attribute name
# (see $SGR_ATTRS). Expands to nothing if colorization is disabled, which is
# what makes it safe to bake the result into cell contents.
sgr() {
	if ! (( COLOR )); then return; fi

	local arg name hex
	local -a params=()
	for arg; do
		case "$arg" in
		fg=*|bg=*)
			name="${arg#??=}"
			hex="${SGR_COLORS[$name]-}"
			[[ $hex ]] || die "sgr: unknown color: $name"
			case "$arg" in
			fg=*) params+=( 38 2 ) ;;
			bg=*) params+=( 48 2 ) ;;
			esac
			params+=( "$(( 16#${hex:0:2} ))" "$(( 16#${hex:2:2} ))" "$(( 16#${hex:4:2} ))" )
			;;
		*)
			[[ ${SGR_ATTRS[$arg]+set} ]] || die "sgr: unknown attribute: $arg"
			params+=( "${SGR_ATTRS[$arg]}" )
			;;
		esac
	done

	if (( ${#params[@]} )); then
		printf '\e[%sm' "$(join ';' "${params[@]}")"
	fi
}

setup_sgr() {
	SGR_OFF="$(sgr reset)"
	SGR_TITLE="$(sgr fg=base1 bold)"
	SGR_TOTAL="$(sgr fg=base2 bold)"

	# Throttling severity. "never" is deliberately near-invisible; the eye
	# should only be caught by the states that actually mean something.
	SGR_NEVER="$(sgr fg=base02 bg=base03)"
	SGR_PAST="$(sgr fg=yellow bg=base03)"
	SGR_NOW="$(sgr fg=base3 bg=red bold)"
	SGR_NONE="$(sgr fg=green)"
}


#
# box drawing
#
# A block is opened with box_open(), filled with box_row()/box_blank(),
# subdivided with box_rule() and terminated with box_close(). All of these
# operate on a *layout*: an array of column specifications, one per column,
# each of the form "<style> <align> <width>".
#
# <style> describes the separator drawn to the *left* of the column (the style
# of the first column is ignored -- the outer border is always solid):
#	hard	solid separator, tick marks on rules
#	bar	ASCII-art separator, tick marks on rules
#	soft	ASCII-art separator, no tick marks on rules
#	none	no separator at all, no tick marks on rules
# <align> is one of l, r, c.
# <width> is the content width in characters (excluding the one space of
# padding added on either side), or "*" to expand the column such that the
# block comes out exactly $BOX_WIDTH characters wide.
#
# Cells may contain SGR sequences; they do not count towards the cell width.
#

declare -A BOX_CHARS_unicode=(
	[h]='─'  [v]='│'  [b]='|'
	[tl]='╭' [tr]='╮' [bl]='╰' [br]='╯'
	[ml]='├' [mr]='┤' [td]='┬' [tu]='┴' [x]='┼'
)

declare -A BOX_CHARS_ascii=(
	[h]='-'  [v]='|'  [b]='|'
	[tl]='|' [tr]='|' [bl]='|' [br]='|'
	[ml]='|' [mr]='|' [td]='+' [tu]='+' [x]='+'
)

setup_box() {
	declare -p "BOX_CHARS_$BOX_CHARSET" &>/dev/null || die "unknown charset: $BOX_CHARSET"
	declare -gn BOX="BOX_CHARS_$BOX_CHARSET"
}

# state of the block currently being drawn
_BOX_NAME=
declare -a _BOX_STYLES=() _BOX_ALIGNS=() _BOX_WIDTHS=()
declare -A _BOX_TICKS=() _BOX_TICKS_PREV=()
_BOX_TOTAL=0

# _box_setup <LAYOUT>: make <LAYOUT> current, remembering the tick marks of the
# previous layout so that a rule can be drawn across the transition.
_box_setup() {
	declare -n layout="$1"
	local spec style align width
	local -a styles=() aligns=() widths=()
	local fixed=0 flex=0 i

	for spec in "${layout[@]}"; do
		read -r style align width <<<"$spec"
		case "$style" in
		hard|bar|soft|none) ;;
		*) die "box: bad column style: $spec" ;;
		esac
		case "$align" in
		l|r|c) ;;
		*) die "box: bad column alignment: $spec" ;;
		esac

		styles+=( "$style" )
		aligns+=( "$align" )
		if [[ $width == '*' ]]; then
			widths+=( -1 )
			(( ++flex )) ||:
		elif [[ $width == +([0-9]) ]]; then
			widths+=( "$width" )
			(( fixed += width )) ||:
		else
			die "box: bad column width: $spec"
		fi
	done

	local n="${#widths[@]}"
	(( n )) || die "box: empty layout: $1"

	# 2 outer borders, 2 padding characters per column, 1 separator in between
	local rest=$(( BOX_WIDTH - (2 + 2*n + (n-1)) - fixed ))
	for (( i = 0; i < n && flex; ++i )); do
		if (( widths[i] >= 0 )); then continue; fi
		# distribute the slack over all flexible columns, leftmost first
		widths[i]=$(( rest > 0 ? (rest + flex - 1) / flex : 0 ))
		(( rest -= widths[i], --flex )) ||:
	done

	_BOX_NAME="$1"
	_BOX_STYLES=( "${styles[@]}" )
	_BOX_ALIGNS=( "${aligns[@]}" )
	_BOX_WIDTHS=( "${widths[@]}" )

	# recompute tick mark offsets (offset 0 is the left border)
	local off=1
	_BOX_TICKS_PREV=()
	for off in "${!_BOX_TICKS[@]}"; do
		_BOX_TICKS_PREV[$off]=1
	done
	_BOX_TICKS=()
	off=1
	for (( i = 0; i < n; ++i )); do
		if (( i )); then
			case "${_BOX_STYLES[i]}" in
			hard|bar) _BOX_TICKS[$off]=1 ;;
			esac
			(( ++off )) ||:
		fi
		(( off += _BOX_WIDTHS[i] + 2 )) ||:
	done
	_BOX_TOTAL=$(( off + 1 ))
}

# _box_cell <OUT> <ALIGN> <WIDTH> <TEXT>: pad <TEXT> to <WIDTH> visible columns.
_box_cell() {
	declare -n _out="$1"
	local align="$2" width="$3" text="$4"
	local plain="${text//$'\e'\[*([0-9;])m/}"
	local pad=$(( width - ${#plain} )) out

	if (( pad <= 0 )); then
		# only truncate what we can measure character by character
		if [[ $plain == "$text" ]]; then
			_out="${text:0:width}"
		else
			_out="$text"
		fi
		return
	fi

	case "$align" in
	l) printf -v out '%s%*s' "$text" "$pad" '' ;;
	r) printf -v out '%*s%s' "$pad" '' "$text" ;;
	c) printf -v out '%*s%s%*s' "$(( pad / 2 ))" '' "$text" "$(( (pad + 1) / 2 ))" '' ;;
	esac
	_out="$out"
}

# _box_draw_rule <LEFT> <RIGHT> [TITLE]
_box_draw_rule() {
	local left="$1" right="$2" title="${3-}"
	local -a chars=()
	local off c

	for (( off = 1; off <= _BOX_TOTAL - 2; ++off )); do
		if [[ ${_BOX_TICKS_PREV[$off]+set} && ${_BOX_TICKS[$off]+set} ]]; then
			c="${BOX[x]}"
		elif [[ ${_BOX_TICKS_PREV[$off]+set} ]]; then
			c="${BOX[tu]}"
		elif [[ ${_BOX_TICKS[$off]+set} ]]; then
			c="${BOX[td]}"
		else
			c="${BOX[h]}"
		fi
		chars+=( "$c" )
	done

	if [[ $title ]]; then
		local text=" $title " i first=2 last
		last=$(( first + ${#text} - 1 ))
		(( last < ${#chars[@]} )) || last=$(( ${#chars[@]} - 1 ))
		for (( i = first; i <= last; ++i )); do
			chars[i]="${text:i-first:1}"
		done
		if (( last >= first )); then
			chars[first]="${SGR_TITLE}${chars[first]}"
			chars[last]="${chars[last]}${SGR_OFF}"
		fi
	fi

	local IFS=''
	printf '%s%s%s\n' "$left" "${chars[*]}" "$right"
}

# box_open <LAYOUT> [TITLE]
box_open() {
	_BOX_TICKS=()
	_box_setup "$1"
	_box_draw_rule "${BOX[tl]}" "${BOX[tr]}" "${2-}"
}

# box_rule [-l <LAYOUT>] [TITLE]: draw an intermediate rule, optionally
# switching to a different layout (tick marks of both layouts are joined).
box_rule() {
	local layout="$_BOX_NAME"
	if [[ ${1-} == -l ]]; then
		layout="$2"
		shift 2
	fi
	_box_setup "$layout"
	_box_draw_rule "${BOX[ml]}" "${BOX[mr]}" "${1-}"
}

box_close() {
	_BOX_TICKS_PREV=()
	local off
	for off in "${!_BOX_TICKS[@]}"; do
		_BOX_TICKS_PREV[$off]=1
	done
	_BOX_TICKS=()
	_box_draw_rule "${BOX[bl]}" "${BOX[br]}"
}

# box_row [-s <SGR>] [CELL...]: draw a data row. With -s, the entire inner
# width of the row (separators and padding included) is wrapped in <SGR>.
box_row() {
	local rowsgr=
	if [[ ${1-} == -s ]]; then
		rowsgr="$2"
		shift 2
	fi

	local i n="${#_BOX_WIDTHS[@]}" cell inner=''
	for (( i = 0; i < n; ++i )); do
		if (( i )); then
			case "${_BOX_STYLES[i]}" in
			hard) inner+="${BOX[v]}" ;;
			bar|soft) inner+="${BOX[b]}" ;;
			none) inner+=' ' ;;
			esac
		fi
		_box_cell cell "${_BOX_ALIGNS[i]}" "${_BOX_WIDTHS[i]}" "${@:i+1:1}"
		inner+=" $cell "
	done

	printf '%s%s%s%s%s\n' \
		"${BOX[v]}" "$rowsgr" "$inner" "${rowsgr:+$SGR_OFF}" "${BOX[v]}"
}

box_blank() {
	box_row
}


#
# vcgencmd
#

# vcgen <ARGS...>: run vcgencmd, converting its in-band error reports into a
# non-zero exit status (vcgencmd itself always exits 0).
vcgen() {
	local out
	out="$(vcgencmd "$@")" || return

	case "$out" in
	'bad argument'*|'Bad'*|'error'*|'Command not registered'*|'VCHI initialization failed'*)
		dbg "vcgencmd $*: $out"
		return 1
		;;
	esac
	printf '%s\n' "$out"
}

# vcgen_value <ARGS...>: as above, but return only the part after the first "=".
vcgen_value() {
	local out
	out="$(vcgen "$@")" || return
	[[ $out == *=* ]] || return 1
	printf '%s\n' "${out#*=}"
}

declare -a CLOCK_DOMAINS=( arm core h264 isp v3d uart pwm emmc pixel vec hdmi dpi )
declare -A CLOCK_LABELS=(
	[arm]='ARM'       [core]='Core (VPU)' [h264]='H.264'  [isp]='ISP'
	[v3d]='V3D (GPU)' [uart]='UART'       [pwm]='PWM'     [emmc]='eMMC / SD'
	[pixel]='Pixel'   [vec]='VEC'         [hdmi]='HDMI'   [dpi]='DPI'
)

declare -a VOLT_DOMAINS=( core sdram_c sdram_i sdram_p )
declare -A VOLT_LABELS=(
	[core]='Core'            [sdram_c]='SDRAM controller'
	[sdram_i]='SDRAM I/O'    [sdram_p]='SDRAM PHY'
)

fmt_hz() {
	local hz="$1"
	if (( hz )); then
		printf '%d.%02d MHz' "$(( hz / 1000000 ))" "$(( (hz % 1000000) / 10000 ))"
	else
		printf 'off'
	fi
}


#
# PMIC
#

# Rails are grouped for display purposes only; the grouping is cosmetic and
# rails not mentioned here are collected into a trailing "Other" group.
declare -a PMIC_GROUPS=(
	'SoC'		'VDD_CORE 0V8_SW 0V8_AON'
	'Memory'	'DDR_VDD2 DDR_VDDQ'
	'System'	'3V3_SYS 1V8_SYS 1V1_SYS'
	'Peripherals'	'3V7_WL_SW HDMI 3V3_DAC 3V3_ADC'
	'Input'		'EXT5V BATT'
)

# Rails summed up into the total board power figure.
#
# XXX: this assumes the listed rails do not overlap, which is *not* verified.
# EXT5V/BATT are excluded because they are not current-sensed at all; 3V3_DAC
# and 3V3_ADC are excluded because they are LDOs believed to be fed from
# 3V3_SYS (and would thus be counted twice), even though they draw ~0 A.
declare -a PMIC_POWER_RAILS=(
	VDD_CORE 0V8_SW 0V8_AON
	DDR_VDD2 DDR_VDDQ
	3V3_SYS 1V8_SYS 1V1_SYS
	3V7_WL_SW HDMI
)

# readings, keyed by rail, kept around for reuse
declare -a PMIC_RAILS=()
declare -A PMIC_VOLTS=() PMIC_AMPS=() PMIC_WATTS=()
PMIC_TOTAL_POWER=

pmic_read() {
	PMIC_RAILS=()
	PMIC_VOLTS=()
	PMIC_AMPS=()
	PMIC_WATTS=()
	PMIC_TOTAL_POWER=

	local out
	out="$(vcgen pmic_read_adc)" || return

	# " 3V7_WL_SW_A current(0)=0.00000000A"
	local name value rail
	local -A seen=()
	while read -r name value; do
		[[ $name && $value == *=* ]] || continue
		value="${value#*=}"
		case "$name" in
		*_A) rail="${name%_A}"; PMIC_AMPS[$rail]="${value%A}" ;;
		*_V) rail="${name%_V}"; PMIC_VOLTS[$rail]="${value%V}" ;;
		*) continue ;;
		esac
		if ! [[ ${seen[$rail]+set} ]]; then
			seen[$rail]=1
			PMIC_RAILS+=( "$rail" )
		fi
	done <<<"$out"

	(( ${#PMIC_RAILS[@]} )) || return 1

	local -a pairs=()
	for rail in "${PMIC_RAILS[@]}"; do
		if [[ ${PMIC_VOLTS[$rail]+set} && ${PMIC_AMPS[$rail]+set} ]]; then
			pairs+=( "$rail ${PMIC_VOLTS[$rail]} ${PMIC_AMPS[$rail]}" )
		fi
	done
	local watts
	printa "${pairs[@]}" \
	| awk '{ printf "%s %.6f\n", $1, $2 * $3 }' \
	| while read -r rail watts; do
		PMIC_WATTS[$rail]="$watts"
	done

	local -a total=()
	for rail in "${PMIC_POWER_RAILS[@]}"; do
		if [[ ${PMIC_WATTS[$rail]+set} ]]; then
			total+=( "${PMIC_WATTS[$rail]}" )
		fi
	done
	PMIC_TOTAL_POWER="$(printa "${total[@]}" | awk '{ sum += $1 } END { printf "%.3f\n", sum }')"
}


#
# throttling
#
# https://www.raspberrypi.com/documentation/computers/os.html#get_throttled
#

# display order, most severe first; bit N is "now", bit N+16 is "since boot"
declare -a THROTTLE_BITS=( 2 3 1 0 )
declare -A THROTTLE_LABELS=(
	[2]='Overall throttled'  [3]='Thermal soft limit'
	[1]='ARM frequency reduced'  [0]='Under-voltage'
)
declare -A THROTTLE_CHIPS=(
	[2]='THROTTLED'  [3]='SOFT-TEMP'  [1]='FREQ'  [0]='UNDER-VOLTAGE'
)

THROTTLED_RAW=
THROTTLED=0

throttle_read() {
	THROTTLED_RAW="$(vcgen_value get_throttled)" || return
	THROTTLED=$(( THROTTLED_RAW ))
}

# throttle_state <BIT>: never | past | now
throttle_state() {
	local bit="$1"
	if (( THROTTLED & (1 << bit) )); then
		echo now
	elif (( THROTTLED & (1 << (bit + 16)) )); then
		echo past
	else
		echo never
	fi
}

# throttle_chip <BIT> <STATE>: render a highlighted, fixed-width status word.
# Without colors, severity is conveyed by capitalization instead.
throttle_chip() {
	local chip="${THROTTLE_CHIPS[$1]}" state="$2" sgr text

	case "$state" in
	now)   sgr="$SGR_NOW";   text="$chip" ;;
	past)  sgr="$SGR_PAST";  text="${chip,,}"; text="${text^}" ;;
	never) sgr="$SGR_NEVER"; text="${chip,,}" ;;
	esac
	if (( COLOR )); then
		text="$chip"
	fi

	printf '%s%s%s' "$sgr" "$text" "$SGR_OFF"
}


#
# blocks
#

declare -a L_FULL=( 'hard c *' )
declare -a L_KV=( 'hard r 24' 'hard r *' )
declare -a L_KVVV=( 'hard r 24' 'hard r 11' 'soft r 11' 'soft r *' )
declare -a L_POWER_HDR=( 'hard r 24' 'hard r 11' 'hard r 11' 'hard r *' )
declare -a L_POWER=( 'hard r 24' 'hard r 11' 'bar r 11' 'bar r *' )
declare -a L_POWER_TOTAL=( 'hard r 24' 'hard r *' )
declare -a L_THROTTLE=( 'hard l 24' 'hard r *' )
declare -a L_THROTTLE_CHIPS=(
	'hard l 11' 'none c 9' 'none c 9' 'none c 4' 'none c 13' 'none l *'
)

# read_dt <NODE>: read a string property from the device tree
read_dt() {
	local path="/proc/device-tree/$1"
	[[ -r $path ]] || return 1
	tr -d '\0' <"$path"
}

block_system() {
	local value

	box_open L_KV 'Raspberry Pi'
	if value="$(read_dt model)" && [[ $value ]]; then
		box_row 'Model' "$value"
	fi
	if value="$(read_dt serial-number)" && [[ $value ]]; then
		box_row 'Serial' "$value"
	fi
	if value="$(vcgen version | sed -nr 's/^version ([0-9a-f]+).*/\1/p')" && [[ $value ]]; then
		box_row 'Firmware' "$value"
	fi
	box_row 'Kernel' "$(uname -r)"
	box_close
}

# throttling display: one row per cause, whole row highlighted by severity
block_throttling_list() {
	local bit sgr text

	if ! (( THROTTLED )); then
		box_open L_FULL "Throttling Causes ($THROTTLED_RAW)"
		box_row -s "$SGR_NONE" 'No throttling observed since boot'
	else
		box_open L_THROTTLE "Throttling Causes ($THROTTLED_RAW)"
		for bit in "${THROTTLE_BITS[@]}"; do
			case "$(throttle_state "$bit")" in
			now)   sgr="$SGR_NOW";   text='THROTTLING NOW' ;;
			past)  sgr="$SGR_PAST";  text='in the past' ;;
			never) sgr="$SGR_NEVER"; text='never' ;;
			esac
			box_row -s "$sgr" "${THROTTLE_LABELS[$bit]}" "$text"
		done
	fi
	box_close
}

# throttling display: 2-row summary (now/past), individually highlighted status words
block_throttling_summary2() {
	local bit
	local -a past=() now=()

	for bit in "${THROTTLE_BITS[@]}"; do
		if (( THROTTLED & (1 << (bit + 16)) )); then
			past+=( "$(throttle_chip "$bit" past)" )
		else
			past+=( "$(throttle_chip "$bit" never)" )
		fi
		if (( THROTTLED & (1 << bit) )); then
			now+=( "$(throttle_chip "$bit" now)" )
		else
			now+=( "$(throttle_chip "$bit" never)" )
		fi
	done

	box_open L_THROTTLE_CHIPS "Throttling Causes ($THROTTLED_RAW)"
	box_blank
	box_row 'In the past' "${past[@]}" ''
	box_row 'Currently' "${now[@]}" ''
	box_blank
	box_close
}

# throttling display: 1-row summary, highlighted by most severe status per cause
block_throttling_summary() {
	local bit
	local -a chips=()

	for bit in "${THROTTLE_BITS[@]}"; do
		chips+=( "$(throttle_chip "$bit" "$(throttle_state "$bit")")" )
	done

	box_open L_THROTTLE_CHIPS "Throttling Causes ($THROTTLED_RAW)"
	box_blank
	box_row 'Throttling' "${chips[@]}" ''
	box_blank
	box_close
}

block_temps() {
	local value

	box_open L_KV 'Temperatures'
	if value="$(vcgen_value measure_temp)"; then
		box_row 'SoC' "$(printf '%.1f C' "${value%\'C}")"
	fi
	if value="$(vcgen_value measure_temp pmic)"; then
		box_row 'PMIC' "$(printf '%.1f C' "${value%\'C}")"
	fi
	box_close
}

block_clocks() {
	local domain value

	box_open L_KV 'Clocks'
	for domain in "${CLOCK_DOMAINS[@]}"; do
		if [[ $domain != arm ]] && ! (( ARG_CLOCKS )); then
			continue
		fi
		if value="$(vcgen_value measure_clock "$domain")"; then
			box_row "${CLOCK_LABELS[$domain]}" "$(fmt_hz "$value")"
		fi
	done
	box_close
}

block_volts() {
	local domain value

	box_open L_KV 'Voltages'
	for domain in "${VOLT_DOMAINS[@]}"; do
		if value="$(vcgen_value measure_volts "$domain")"; then
			box_row "${VOLT_LABELS[$domain]}" "$(printf '%.4f V' "${value%V}")"
		fi
	done
	box_close
}

block_ring_osc() {
	local out index freq volts temp

	out="$(vcgen read_ring_osc)" || return 0
	regex_chk "$out" \
		"read_ring_osc\(([0-9]+)\)=([0-9.]+)MHz \(@([0-9.]+)V\) \((-?[0-9.]+)'C\)" \
		index freq volts temp \
	|| return 0

	box_open L_KVVV 'Ring Oscillator'
	box_row "Ring oscillator #$index" \
		"$(printf '%.3f MHz' "$freq")" \
		"$(printf '%.4f V' "$volts")" \
		"$(printf '%.1f C' "$temp")"
	box_close
}

block_power() {
	local -A shown=()
	local i group rail
	local -a rails=() ungrouped=()

	box_open L_POWER_HDR 'Power Rails'
	box_row '' 'Voltage' 'Current' 'Power'

	for (( i = 0; i < ${#PMIC_GROUPS[@]}; i += 2 )); do
		group="${PMIC_GROUPS[i]}"
		read -ra rails <<<"${PMIC_GROUPS[i+1]}"

		local -a present=()
		for rail in "${rails[@]}"; do
			if [[ ${PMIC_VOLTS[$rail]+set} || ${PMIC_AMPS[$rail]+set} ]]; then
				present+=( "$rail" )
				shown[$rail]=1
			fi
		done
		(( ${#present[@]} )) || continue

		box_rule -l L_POWER "$group"
		for rail in "${present[@]}"; do
			_power_row "$rail"
		done
	done

	for rail in "${PMIC_RAILS[@]}"; do
		if ! [[ ${shown[$rail]+set} ]]; then
			ungrouped+=( "$rail" )
		fi
	done
	if (( ${#ungrouped[@]} )); then
		box_rule 'Other'
		for rail in "${ungrouped[@]}"; do
			_power_row "$rail"
		done
	fi

	box_rule -l L_POWER_TOTAL
	box_row -s "$SGR_TOTAL" 'Total board power' "$(printf '%.3f W' "$PMIC_TOTAL_POWER")"
	box_close
}

_power_row() {
	local rail="$1" volts='' amps='' watts=''

	if [[ ${PMIC_VOLTS[$rail]+set} ]]; then
		printf -v volts '%.4f V' "${PMIC_VOLTS[$rail]}"
	fi
	if [[ ${PMIC_AMPS[$rail]+set} ]]; then
		printf -v amps '%.4f A' "${PMIC_AMPS[$rail]}"
	fi
	if [[ ${PMIC_WATTS[$rail]+set} ]]; then
		printf -v watts '%.3f W' "${PMIC_WATTS[$rail]}"
	fi

	box_row "$rail" "$volts" "$amps" "$watts"
}


#
# args
#

declare -A _args=(
	[-h\|--help]=ARG_USAGE
	[-c\|--clocks]=ARG_CLOCKS
	[-P\|--no-power]=ARG_NO_POWER
	[-t\|--throttling:]="ARG_THROTTLING"
	[-w\|--width:]=ARG_WIDTH
	[--ascii]=ARG_ASCII
	[--color::]="ARG_COLOR default=auto"
)
parse_args _args "$@" || usage
[[ ! $ARG_USAGE ]] || usage

: "${ARG_THROTTLING=1}"
case "$ARG_THROTTLING" in
1|2|3|all) ;;
*) usage "bad throttling style: ${ARG_THROTTLING@Q}" ;;
esac

if [[ $ARG_WIDTH ]]; then
	if ! [[ $ARG_WIDTH == +([0-9]) ]] || (( ARG_WIDTH < BOX_WIDTH_MIN )); then
		usage "bad width: $ARG_WIDTH (minimum: $BOX_WIDTH_MIN)"
	fi
	BOX_WIDTH="$ARG_WIDTH"
fi

if [[ $ARG_ASCII ]]; then
	BOX_CHARSET=ascii
fi

case "${ARG_COLOR:-auto}" in
always) COLOR=1 ;;
never) COLOR=0 ;;
auto) if [[ -t 1 && -z ${NO_COLOR-} ]]; then COLOR=1; else COLOR=0; fi ;;
*) usage "bad color mode: $ARG_COLOR" ;;
esac


#
# main
#

command -v vcgencmd &>/dev/null || die "vcgencmd not found (not a Raspberry Pi?)"

setup_sgr
setup_box

throttle_read || die "failed to read the throttling status"
if ! (( ARG_NO_POWER )); then
	pmic_read || warn "failed to read the PMIC ADCs, skipping power rails"
fi

block_system
case "$ARG_THROTTLING" in
1) block_throttling_summary ;;
2) block_throttling_summary2 ;;
3) block_throttling_list ;;
all) block_throttling_list; block_throttling_summary2; block_throttling_summary ;;
esac
block_temps
block_clocks
block_volts
block_ring_osc
if (( ${#PMIC_RAILS[@]} )); then
	block_power
fi
