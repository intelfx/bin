#!/bin/bash

set -eo pipefail
shopt -s lastpipe
shopt -s extglob

# we both parse and print floating-point numbers, and we measure box-drawing
# characters with ${#var}
unset LANG "${!LC_@}"
export LANG=C.UTF-8

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
LOOP_INTERVAL=2

_usage() {
	cat <<EOF
Usage: ${LIB_ARGV0} [OPTIONS]

Display Raspberry Pi throttling state, temperatures, fan, clocks, voltages, and
PMIC per-rail power, decoded from vcgencmd(1) and sysfs.

Options:
	-c, --clocks		Report GPU clock domains in addition to ARM
	-C, --all-clocks	Report all known clock domains
	-P, --no-power		Do not read the PMIC ADCs (Pi 5 only)
	-t, --throttling=STYLE	Throttling display style, 1-4 or "all" (def.: 1)
					1: one-line summary
					2: two-line display
					3: list of reasons
					4: list of reasons (always expanded)
	-l, --loop[=SECONDS]	Redraw in place until interrupted, with
					optional redraw interval (default: $LOOP_INTERVAL seconds)
	-w, --width=N		Block width, in characters
				(default: $BOX_WIDTH, minimum: $BOX_WIDTH_MIN)
	-D, --debug		Report per-frame render time and fork count
	    --ascii		Draw blocks with ASCII instead of Unicode
	    --color=WHEN	Colorize output: always, auto or never
				(default: auto; honors \$TERM and \$NO_COLOR)
	    --term=WHEN		Use terminal control sequences: always, auto
				or never (default: auto; honors \$TERM)
EOF
}


#
# ANSI SGR (Solarized palette)
#

# Solarized, as ANSI palette indices rather than literal colors, so that the
# output follows whichever variant (dark or light) the terminal is themed with
# -- base03..base3 swap ends between the two, and hardcoding either is wrong.
#
#	name    dark      light     ANSI  terminal color
#	base03  #002b36   #fdf6e3   8     brblack
#	base02  #073642   #eee8d5   0     black
#	base01  #586e75   #93a1a1   10    brgreen
#	base00  #657b83   #839496   11    bryellow
#	base0   #839496   #657b83   12    brblue
#	base1   #93a1a1   #586e75   14    brcyan
#	base2   #eee8d5   #073642   7     white
#	base3   #fdf6e3   #002b36   15    brwhite
#	(accents are identical in both variants)
declare -A SGR_COLORS=(
	[base03]=8   [base02]=0   [base01]=10  [base00]=11
	[base0]=12   [base1]=14   [base2]=7    [base3]=15
	[yellow]=3   [orange]=9   [red]=1      [magenta]=5
	[violet]=13  [blue]=4     [cyan]=6     [green]=2
)

declare -A SGR_ATTRS=(
	[reset]=0  [bold]=1   [dim]=2     [italic]=3
	[under]=4  [blink]=5  [invert]=7  [strike]=9
)

STYLE_TITLE="fg=base1 bold"
STYLE_FOOTER="fg=base01"
STYLE_TOTAL="fg=base2 bold"

# Throttling severity. "never" is deliberately near-invisible; the eye
# should only be caught by the states that actually mean something.
STYLE_NEVER="fg=base02" #bg=base03
STYLE_PAST="fg=yellow" #bg=base03
STYLE_NOW="fg=base3 bg=red bold"
STYLE_NONE="fg=green"

setup_sgr() {
	sgr -v SGR_OFF reset
}

# sgr [-v VAR] <ATTR...>: build an SGR escape sequence.
# ATTRs are split on spaces and interpreted as a list of elements, where each
# is either "fg=COLOR"/"bg=COLOR" (see $SGR_COLORS), "fg=default"/"bg=default",
# or an attribute name (see $SGR_ATTRS).
# -v VAR: write the output to a variable VAR (`printf -v VAR`) instead of stdout.
# Produces empty output if $COLOR is zero.
sgr() {
	# NB: `_`-prefix all locals because we assign to a name in the outer scope

	local -a _var=()
	if [[ $1 == -v ]]; then
		_var=(-v "$2")
		# clear the output variable
		printf -v "$2" ''
		shift 2
	fi

	if ! (( COLOR )); then return; fi

	local _arg _name _color
	local -a _params=()
	# shellcheck disable=SC2048  # arguments encode a whitespace-separated list
	for _arg in $*; do
		case "$_arg" in
		fg=default)
			_params+=( 39 ) ;;
		bg=default)
			_params+=( 49 ) ;;
		fg=*|bg=*)
			_name="${_arg#??=}"
			_color="${SGR_COLORS[$_name]-}"
			[[ $_color ]] || die "sgr: unknown color: $_name"
			case "$_arg" in
			fg=*) _params+=( 38 5 "$_color" ) ;;
			bg=*) _params+=( 48 5 "$_color" ) ;;
			esac
			;;
		*)
			[[ ${SGR_ATTRS[$_arg]+set} ]] || die "sgr: unknown attribute: $_arg"
			_params+=( "${SGR_ATTRS[$_arg]}" )
			;;
		esac
	done

	if (( ${#_params[@]} )); then
		local IFS=';'
		# shellcheck disable=SC2059  # $_var[@] contains flags only
		printf "${_var[@]}" '\e[%sm' "${_params[*]}"
	fi
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

# _box_rule_text <CHARS> <TEXT> <ALIGN> <STYLE>: overwrite a part of a rule
# (given as an array of single characters) with <TEXT>, rendered as <STYLE>.
_box_rule_text() {
	declare -n _chars="$1"
	local text=" $2 " align="$3" style="$4"
	local i first last textsgr

	# both alignments leave two rule characters between the text and the border
	case "$align" in
	l) first=2 ;;
	r) first=$(( ${#_chars[@]} - 2 - ${#text} )) ;;
	esac
	(( first >= 2 )) || first=2
	last=$(( first + ${#text} - 1 ))
	(( last < ${#_chars[@]} )) || last=$(( ${#_chars[@]} - 1 ))
	(( last >= first )) || return 0

	for (( i = first; i <= last; ++i )); do
		_chars[i]="${text:i-first:1}"
	done
	sgr -v textsgr "$style"
	_chars[first]="${textsgr}${_chars[first]}"
	_chars[last]="${_chars[last]}${SGR_OFF}"
}

# _box_draw_rule <LEFT> <RIGHT> [TITLE] [FOOTER]: titles are drawn on the left,
# footers on the right.
_box_draw_rule() {
	local left="$1" right="$2" title="${3-}" footer="${4-}"
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

	[[ ! $title ]] || _box_rule_text chars "$title" l "$STYLE_TITLE"
	[[ ! $footer ]] || _box_rule_text chars "$footer" r "$STYLE_FOOTER"

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

# box_close [FOOTER]: close the block, embedding FOOTER into the closing line
# (right-aligned, as opposed to the left-aligned title on the opening line).
box_close() {
	local footer="${1-}"

	_BOX_TICKS_PREV=()
	local off
	for off in "${!_BOX_TICKS[@]}"; do
		_BOX_TICKS_PREV[$off]=1
	done
	_BOX_TICKS=()
	_box_draw_rule "${BOX[bl]}" "${BOX[br]}" '' "$footer"
}

# box_reclose <FOOTER>: rewind over the closing line drawn by box_close() and
# draw it again, this time with FOOTER. For text that is only known once the
# block has been drawn.
#
# Requires the ability to address the terminal ($TERM_CTL); without it, FOOTER
# is emitted as a separate line instead, aligned to the right edge of the block.
# NB: relies on box_close() leaving the tick marks of the block behind in
# $_BOX_TICKS_PREV, so that the rule comes out exactly as it did the first time.
box_reclose() {
	local footer="$1"

	if (( TERM_CTL )); then
		printf '%s' "$CSI_CPL"
		_box_draw_rule "${BOX[bl]}" "${BOX[br]}" '' "$footer"
	else
		printf '%*s\n' "$_BOX_TOTAL" "($footer)"
	fi
}

# box_row [-s|-S <STYLE>] [CELL...]: draw a data row.
# -s STYLE: the entire inner width of the row (separators and paddings included) is rendered as <STYLE>.
# -S STYLE: the contents of the cells of the row are separately rendered as <STYLE>.
#
# Policy decisions made by this function:
# - if row foreground is set, all separators are forcibly drawn in plain foreground;
# - if row background is set, all separators are not drawn (behave as if the style contains `none`).
box_row() {
	local row_style cell_style
	while (( $# )); do
		case "$1" in
		-s) shift; row_style="$1" ;;
		-S) shift; cell_style="$1" ;;
		--) shift; break ;;
		-*) die "box_row: invalid invocation" ;;
		*) break ;;
		esac
		shift
	done

	local rowsgr cellsgr sepsgr sep_hide
	sgr -v rowsgr "$row_style"
	sgr -v cellsgr "$cell_style"
	if [[ $rowsgr && $row_style == *"bg="* ]]; then
		sep_hide=1
	elif [[ $rowsgr && $row_style == *"fg="* ]]; then
		sgr -v sepsgr "fg=default"
	fi

	local i n="${#_BOX_WIDTHS[@]}" cell sep inner=''
	for (( i = 0; i < n; ++i )); do
		if (( i )); then
			case "${_BOX_STYLES[i]}" in
			hard) sep="${BOX[v]}" ;;
			bar|soft) sep="${BOX[b]}" ;;
			none) sep=' ' ;;
			esac

			if [[ $sep_hide ]]; then
				inner+=' '
			elif [[ $sepsgr && $sep != ' ' ]]; then
				inner+="$sepsgr$sep$rowsgr"
			else
				inner+="$sep"
			fi
		fi
		_box_cell cell "${_BOX_ALIGNS[i]}" "${_BOX_WIDTHS[i]}" \
			"$cellsgr${*:i+1:1}${cellsgr:+$SGR_OFF}"
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

# TODO: sort clock domains by applicability (Pi3 and earlier, Pi4-only, Pi5-only)
declare -a CLOCK_DOMAINS=( arm core h264 isp v3d uart pwm emmc pixel vec hdmi dpi )
declare -a CLOCK_DOMAINS_ESSENTIAL=( arm core v3d )
declare -a CLOCK_DOMAINS_ARM=( arm )
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
# device tree
#

# read_dt <NODE>: read a string property from the device tree
read_dt() {
	local path="/proc/device-tree/$1"
	[[ -r $path ]] || return 1
	tr -d '\0' <"$path"
}

# read_dt_u32 <OUT> <NODE>: read a 32-bit cell property from the device tree.
read_dt_u32() {
	# NB: `_`-prefix all locals because we take a name from the outer scope
	declare -n _out="$1"
	local _path="/proc/device-tree/$2"
	[[ -r $_path ]] || return 1

	# device tree cells are big-endian; read with od(1) and strip whitespace
	local _value
	od -An -t u4 -w4 --endian=big "$_path" 2>/dev/null | read -r _value || return 1

	_out="$_value"
}

# read_dt_u32_array <OUT> <NODE>: read a property of several 32-bit cells.
read_dt_u32_array() {
	declare -n _cells="$1"
	local _path="/proc/device-tree/$2"
	[[ -r $_path ]] || return 1

	local -a _values
	readarray -t _values < <(od -An -t u4 -w4 --endian=big "$_path" 2>/dev/null)
	(( ${#_values[@]} )) || return 1

	# od(1) right-aligns each cell within a fixed field width
	_cells=( "${_values[@]//[[:space:]]/}" )
}


#
# hwmon
#

# find_hwmon <OUT> <NAME>: locate the sysfs directory of the hwmon device
# registered under <NAME>. Hwmon indices are not stable, hence the search.
find_hwmon() {
	declare -n _out="$1"
	local _dir

	for _dir in /sys/class/hwmon/hwmon*; do
		[[ -r $_dir/name ]] || continue
		[[ $(<"$_dir/name") == "$2" ]] || continue
		_out="$_dir"
		return 0
	done
	return 1
}

# read_hwmon <OUT> <NAME> <ATTR>: read attribute <ATTR> of the hwmon device
# registered under <NAME>.
read_hwmon() {
	declare -n _out="$1"
	local _hwmon

	find_hwmon _hwmon "$2" || return 1
	[[ -r $_hwmon/$3 ]] || return 1
	_out="$(<"$_hwmon/$3")"
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
# power supply
#
# The Raspberry Pi 5 firmware negotiates a power contract with the USB-C PSU
# and publishes the outcome under /proc/device-tree/chosen/power; the USB ports
# are restricted to 600 mA in total unless the PSU can supply enough for the
# 1.6 A profile. Earlier models do not have this node at all.
#

PSU_PRESENT=0
PSU_MAX_CURRENT=	# mA the power supply advertises
PSU_USB_MAX_CURRENT=	# whether the high-current USB profile is enabled
PSU_USB_OVERCURRENT=	# whether an USB overcurrent condition was detected

psu_read() {
	PSU_PRESENT=0
	PSU_MAX_CURRENT=
	PSU_USB_MAX_CURRENT=
	PSU_USB_OVERCURRENT=

	[[ -d /proc/device-tree/chosen/power ]] || return 1

	read_dt_u32 PSU_MAX_CURRENT chosen/power/max_current ||:
	read_dt_u32 PSU_USB_MAX_CURRENT chosen/power/usb_max_current_enable ||:
	read_dt_u32 PSU_USB_OVERCURRENT chosen/power/usb_over_current_detected ||:

	[[ $PSU_MAX_CURRENT || $PSU_USB_MAX_CURRENT || $PSU_USB_OVERCURRENT ]] || return 1
	PSU_PRESENT=1
}


#
# fan
#
# The Raspberry Pi 5 firmware probes the 4-pin fan connector and only adds the
# fan node to the device tree if something answers, so on a board without a fan
# the hwmon device is simply absent.
#
# The fan is driven by the kernel thermal framework rather than by the
# firmware: the config.txt fan_tempN{,_hyst,_speed} parameters are device tree
# overrides that the firmware applies to the trip points of the CPU thermal
# zone and to the cooling levels of the fan node. Both are readable back out of
# /proc/device-tree, so recovering the curve does not involve config.txt.
#
# NB: pwm1_enable is not the usual hwmon manual/automatic selector. pwm-fan(4)
# uses it to pick what happens to the PWM output and to the fan regulator once
# a zero duty cycle is requested: 0 turns off both, 1 stops the PWM but keeps
# the regulator up, 2 keeps both up, 3 turns off both. The driver hardcodes 1
# at probe time and only ever changes it on an explicit write, which is why it
# reads 1 on a fan that is very much under automatic control -- thermal control
# runs through the cooling device interface and never looks at this attribute.
#

FAN_PRESENT=0
FAN_DIR=	# sysfs directory of the hwmon device
FAN_RPM=	# tachometer reading, if the fan has a tachometer
FAN_PWM=	# duty cycle currently requested, out of 255
FAN_ENABLE=	# pwm-fan power mode, see above
FAN_CURVE=()	# control curve as "<temperature, mC>:<duty cycle>", ascending

fan_read() {
	FAN_RPM=
	FAN_PWM=
	FAN_ENABLE=

	if ! (( FAN_PRESENT )); then
		find_hwmon FAN_DIR pwmfan || return 1
		FAN_PRESENT=1
		fan_curve_read ||:
	fi

	[[ ! -r $FAN_DIR/fan1_input ]] || FAN_RPM="$(<"$FAN_DIR/fan1_input")"
	[[ ! -r $FAN_DIR/pwm1 ]] || FAN_PWM="$(<"$FAN_DIR/pwm1")"
	[[ ! -r $FAN_DIR/pwm1_enable ]] || FAN_ENABLE="$(<"$FAN_DIR/pwm1_enable")"
}

# fan_curve_read: recover the control curve by joining the cooling levels of
# the fan node with the trip points that the cooling maps of the thermal zones
# bind it to. Static, hence read once rather than per frame.
fan_curve_read() {
	local node phandle zone trip map type temp tripref
	local -a levels cdev zones trips maps
	# trip point temperatures of the zone being walked, keyed by phandle
	local -a points

	FAN_CURVE=()

	# of_node points into /sys/firmware/devicetree/base, the very same tree
	node="$(readlink -f "$FAN_DIR/of_node")" || return 1
	node="${node#*/devicetree/base/}/"
	[[ $node != /* ]] || return 1

	read_dt_u32 phandle "${node}phandle" || return 1
	read_dt_u32_array levels "${node}cooling-levels" || return 1

	zones=( /proc/device-tree/thermal-zones/*/ )
	for zone in "${zones[@]#/proc/device-tree/}"; do
		# the cooling maps refer to trip points by phandle and by nothing
		# else, so index the whole set of them up front
		points=()
		trips=( "/proc/device-tree/${zone}trips/"*/ )
		for trip in "${trips[@]#/proc/device-tree/}"; do
			# the critical trip is the thermal shutdown, not a fan step
			type="$(read_dt "${trip}type")" || continue
			[[ $type == active || $type == passive ]] || continue
			read_dt_u32 tripref "${trip}phandle" || continue
			read_dt_u32 temp "${trip}temperature" || continue
			points[tripref]="$temp"
		done

		maps=( "/proc/device-tree/${zone}cooling-maps/"*/ )
		for map in "${maps[@]#/proc/device-tree/}"; do
			# <phandle, lowest state, highest state>; a map may name
			# several cooling devices, but ours can only be the first
			read_dt_u32_array cdev "${map}cooling-device" || continue
			(( ${#cdev[@]} >= 2 && cdev[0] == phandle )) || continue
			(( cdev[1] < ${#levels[@]} )) || continue

			read_dt_u32 tripref "${map}trip" || continue
			[[ ${points[tripref]+set} ]] || continue

			FAN_CURVE+=( "${points[tripref]}:${levels[cdev[1]]}" )
		done
	done

	(( ${#FAN_CURVE[@]} )) || return 1
	# the maps come out in glob order, which is not temperature order
	readarray -t FAN_CURVE < <(printf '%s\n' "${FAN_CURVE[@]}" | sort -n)
}


#
# throttling
#
# https://www.raspberrypi.com/documentation/computers/os.html#get_throttled
#

# display order, most severe first; bit N is "now", bit N+16 is "since boot"
declare -a THROTTLE_BITS=( 2 0 1 3 )
declare -A THROTTLE_LABELS=(
	[2]='Overall throttled'
	[0]='Low voltage'
	[1]='ARM frequency reduced'
	[3]='Thermal soft limit'
)
declare -A THROTTLE_CHIPS=(
	[2]='THROTTLED'  [0]='LOW-VOLTAGE'  [1]='FREQ-CAP'  [3]='SOFT-TEMP'
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
	local chip="${THROTTLE_CHIPS[$1]}" state="$2" style textsgr text

	case "$state" in
	now)   style="$STYLE_NOW";   text="$chip" ;;
	past)  style="$STYLE_PAST";  text="${chip,,}"; text="${text^}" ;;
	never) style="$STYLE_NEVER"; text="${chip,,}" ;;
	esac
	if (( COLOR )); then
		text="$chip"
	fi

	sgr -v textsgr "$style"
	printf '%s%s%s' "$textsgr" "$text" "$SGR_OFF"
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
	'hard l *' 'none c 9' 'none c 11' 'none c 8' 'none c 9'
)

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
	local bit style text expand=0
	if [[ $1 == --expand ]]; then
		expand=1
		shift
	fi

	if ! (( THROTTLED || expand )); then
		box_open L_FULL "Throttling Causes ($THROTTLED_RAW)"
		box_row -s "$STYLE_NONE" 'No throttling observed since boot'
	else
		box_open L_THROTTLE "Throttling Causes ($THROTTLED_RAW)"
		for bit in "${THROTTLE_BITS[@]}"; do
			case "$(throttle_state "$bit")" in
			now)   style="$STYLE_NOW";   text='THROTTLING NOW' ;;
			past)  style="$STYLE_PAST";  text='in the past' ;;
			never) style="$STYLE_NEVER"; text='never' ;;
			esac
			box_row -s "$style" "${THROTTLE_LABELS[$bit]}" "$text"
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
	box_row 'In the past' "${past[@]}"
	box_row 'Currently' "${now[@]}"
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
	box_row 'Summary' "${chips[@]}"
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
	# the RP1 I/O controller only exists on the Raspberry Pi 5; its sensor is
	# untrimmed and the driver quantizes it to ~0.6 C, so it is good for
	# trends only
	if read_hwmon value rp1_adc temp1_input; then
		box_row 'RP1' "$(printf '%.1f C' "${value}e-3")"
	fi
	box_close
}

block_fan() {
	local point temp duty entry value sep
	local last_duty
	local sgron sgroff="$SGR_OFF"

	box_open L_KV 'Fan'
	if [[ $FAN_RPM ]]; then
		box_row 'Speed' "$FAN_RPM rpm"
	fi
	if [[ $FAN_PWM ]]; then
		box_row 'Duty cycle' \
			"$(printf '%d/255 (%d%%)' "$FAN_PWM" "$(( (FAN_PWM * 100 + 127) / 255 ))")"
	fi
	# 0 and 3 both cut the PWM output regardless of what the thermal
	# framework asks for, i.e. someone has taken the fan out of service
	if [[ $FAN_ENABLE == 0 || $FAN_ENABLE == 3 ]]; then
		box_row -s "$STYLE_NOW" 'Control' 'DISABLED'
	fi
	if (( ${#FAN_CURVE[@]} )); then
		sgr -v sgron "$STYLE_TOTAL"
		value=
		sep=
		last_duty=0
		for point in "${FAN_CURVE[@]}"; do
			temp="${point%:*}"
			duty="${point#*:}"
			if [[ $duty == '*' ]]
			then duty="$last_duty"
			else last_duty="$duty"
			fi

			printf -v entry '%.1fC %d%%' \
				"${temp}e-3" "$(( (duty * 100 + 127) / 255 ))"
			# mark the point the fan is currently sitting at
			[[ $duty != "$FAN_PWM" ]] || entry="$sgron$entry$sgroff"
			value+="$sep$entry"
			sep='  '
		done
		box_row 'Curve' "$value"
	fi
	box_close
}

block_clocks() {
	local domain value
	local -a clocks

	if (( ARG_ALL_CLOCKS )); then
		clocks=("${CLOCK_DOMAINS[@]}")
	elif (( ARG_CLOCKS )); then
		clocks=("${CLOCK_DOMAINS_ESSENTIAL[@]}")
	else
		clocks=("${CLOCK_DOMAINS_ARM[@]}")
	fi

	box_open L_KV 'Clocks'
	for domain in "${clocks[@]}"; do
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

block_psu() {
	local value

	box_open L_KV 'Power Supply'
	if [[ $PSU_MAX_CURRENT ]]; then
		printf -v value '%d.%d A' \
			"$(( PSU_MAX_CURRENT / 1000 ))" "$(( (PSU_MAX_CURRENT % 1000) / 100 ))"
		box_row 'Maximum supply current' "$value"
	fi
	if [[ $PSU_USB_MAX_CURRENT ]]; then
		if (( PSU_USB_MAX_CURRENT )); then value='enabled'; else value='disabled'; fi
		box_row 'USB high current mode' "$value"
	fi
	if [[ $PSU_USB_OVERCURRENT ]]; then
		if (( PSU_USB_OVERCURRENT )); then
			box_row -s "$STYLE_NOW" 'USB overcurrent' 'DETECTED'
		else
			box_row 'USB overcurrent' 'never'
		fi
	fi
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
	box_row -S "$STYLE_TOTAL" 'Total board power' "$(printf '%.3f W' "$PMIC_TOTAL_POWER")"
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
# terminal control
#
# ryzen_monitor(1) redraws with ESC[1;1H ESC[2J, i.e. it blanks the whole
# screen and paints it again; on a slow or remote terminal that is visible as
# a flicker, because the screen is briefly empty. Instead, home the cursor and
# overwrite in place: every line is terminated with EL (erase to end of line)
# to clean up after a line that got shorter, and the frame is terminated with
# ED (erase to end of display) to clean up after a frame that got shorter.
#
# Cursor hiding is likewise bracketed around the whole run rather than emitted
# per iteration (ryzen_monitor hides it only *after* painting the first frame,
# so the cursor is visible for the duration of that frame).
#

CSI_HOME=$'\e[H'		# cursor to 1;1
CSI_CPL=$'\e[F'			# cursor to the start of the previous line
CSI_EL=$'\e[K'			# erase from cursor to end of line
CSI_ED=$'\e[J'			# erase from cursor to end of display
CSI_CURSOR_HIDE=$'\e[?25l'	# DECTCEM
CSI_CURSOR_SHOW=$'\e[?25h'

# whether we may drive the terminal (as opposed to just writing lines out)
TERM_CTL=0

term_begin() {
	(( TERM_CTL )) || return 0
	eval "$(globaltraps)"
	# shellcheck disable=SC2016 # trap bodies are expanded when they run
	ltrap 'printf "%s" "$CSI_CURSOR_SHOW"'
	# make sure the EXIT trap above also runs when we are interrupted
	trap 'exit 130' INT
	trap 'exit 143' TERM
	printf '%s' "$CSI_CURSOR_HIDE"
}

# term_frame <TEXT>: emit one full-screen frame, overwriting the previous one
term_frame() {
	local frame="$1"

	if ! (( TERM_CTL )); then
		printf '%s\n' "$frame"
		return
	fi
	printf '%s%s%s\n%s' \
		"$CSI_HOME" "${frame//$'\n'/"$CSI_EL"$'\n'}" "$CSI_EL" "$CSI_ED"
}


#
# debug instrumentation
#

_FRAME_TIME=0
_FRAME_PID=0

# _pid_sample <OUT>: sample the kernel PID counter, at the cost of one fork
# (a background job runs in a subshell even if it is a builtin).
_pid_sample() {
	# NB: `_`-prefix all locals because we take a name from the outer scope
	declare -n _out="$1"
	: &
	_out="$!"
	wait "$_out" &>/dev/null ||:
}

frame_begin() {
	(( ARG_DEBUG )) || return 0
	_pid_sample _FRAME_PID
	_FRAME_TIME="${EPOCHREALTIME/./}"
}

# frame_stats <OUT>: time elapsed and processes spawned since frame_begin().
# The fork count is approximate: PIDs are handed out sequentially, so anything
# else forking on the system in the meantime is counted in as well.
frame_stats() {
	declare -n _out="$1"
	local _pid _elapsed _forks

	_elapsed=$(( ${EPOCHREALTIME/./} - _FRAME_TIME ))
	_pid_sample _pid
	# less one for the fork _pid_sample() just did itself
	_forks=$(( _pid - _FRAME_PID - 1 ))
	if (( _forks < 0 )); then
		# the counter wrapped around
		_forks=$(( _forks + $(</proc/sys/kernel/pid_max) ))
	fi

	printf -v _out '%d.%03d ms, %d forks' \
		"$(( _elapsed / 1000 ))" "$(( _elapsed % 1000 ))" "$_forks"
}


#
# refresh & render
#

PMIC_WARNED=0

refresh() {
	throttle_read || die "failed to read the throttling status"
	psu_read ||:
	fan_read ||:

	if ! (( ARG_NO_POWER )) && ! pmic_read; then
		# in --loop mode, complain once rather than on every iteration
		if ! (( PMIC_WARNED )); then
			PMIC_WARNED=1
			warn "failed to read the PMIC ADCs, skipping power rails"
		fi
	fi
}

render() {
	block_system
	case "$ARG_THROTTLING" in
	1) block_throttling_summary ;;
	2) block_throttling_summary2 ;;
	3) block_throttling_list ;;
	4) block_throttling_list --expand ;;
	all) block_throttling_list; block_throttling_summary2; block_throttling_summary ;;
	esac
	block_temps
	if (( FAN_PRESENT )); then
		block_fan
	fi
	block_clocks
	block_volts
	block_ring_osc
	if (( PSU_PRESENT )); then
		block_psu
	fi
	if (( ${#PMIC_RAILS[@]} )); then
		block_power
	fi

	# reclose the last block, so that the stats cover the entire frame
	if (( ARG_DEBUG )); then
		local stats
		frame_stats stats
		box_reclose "$stats"
	fi
}


#
# args
#

declare -A _args=(
	[-h\|--help]=ARG_USAGE
	[-c\|--clocks]=ARG_CLOCKS
	[-C\|--all-clocks]=ARG_ALL_CLOCKS
	[-P\|--no-power]=ARG_NO_POWER
	[-t\|--throttling:]="ARG_THROTTLING"
	[-l\|--loop::]="ARG_LOOP default=$LOOP_INTERVAL"
	[-w\|--width:]=ARG_WIDTH
	[-D\|--debug]=ARG_DEBUG
	[--ascii]=ARG_ASCII
	[--color::]="ARG_COLOR default=auto"
	[--term::]="ARG_TERM default=auto"
)
parse_args _args "$@" || usage
[[ ! $ARG_USAGE ]] || usage

: "${ARG_THROTTLING=1}"
case "$ARG_THROTTLING" in
1|2|3|4|all) ;;
*) usage "bad throttling style: ${ARG_THROTTLING@Q}" ;;
esac

if (( ARG_CLOCKS + ARG_ALL_CLOCKS > 1 )); then
	usage "-c/--clocks and -C/--all-clocks are mutually exclusive"
fi


if [[ $ARG_LOOP ]]; then
	if ! [[ $ARG_LOOP == +([0-9])?(.+([0-9])) ]] || [[ $ARG_LOOP == +(0|.) ]]; then
		usage "bad loop interval: $ARG_LOOP"
	fi
fi

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
auto) if [[ -t 1 && ${TERM-} != dumb && -z ${NO_COLOR-} ]]; then COLOR=1; else COLOR=0; fi ;;
*) usage "bad color mode: $ARG_COLOR" ;;
esac

case "${ARG_TERM:-auto}" in
always) TERM_CTL=1 ;;
never) TERM_CTL=0 ;;
auto) if [[ -t 1 && ${TERM-} != dumb ]]; then TERM_CTL=1; else TERM_CTL=0; fi ;;
*) usage "bad terminal mode: $ARG_TERM" ;;
esac


#
# main
#

command -v vcgencmd &>/dev/null || die "vcgencmd not found (not a Raspberry Pi?)"

setup_sgr
setup_box

if ! [[ $ARG_LOOP ]]; then
	frame_begin
	refresh
	render
	exit
fi

term_begin
while :; do
	frame_begin
	refresh
	term_frame "$(render)"
	sleep "$ARG_LOOP"
done
