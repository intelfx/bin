#!/bin/bash

set -eo pipefail
shopt -s lastpipe

# shellcheck source=../lib/lib.sh
. lib.sh


#
# This is a "text preview" script for SQLite databases.
# It provides a quick overview of the database structure and contents.
# Intended for integration into CLI/TUI workflows, such as vifm's fileviewer
# or preview commands in fzf-based navigators.
#
# Output of this script is valid SQL and can be highlighted using e.g. `bat --language=sql`.
#


#
# functions
#

emit() {
	# emit freeform text as SQL comment
	printf -- "-- %s\n" "$@"
}

emitf() {
	# emit freeform text as SQL comment, printf-style
	local fmt="$1"
	shift
	# shellcheck disable=SC2059
	printf -- "-- $fmt\n" "$@"
}

emit_stderr() {
	# capture a stream (e.g. a command's stderr) and emit them as SQL comments
	# to keep the overall output of this script valid SQL
	local line
	while IFS= read -r line; do
		emitf "STDERR: %s" "$line"
	done
}

log() {
	emitf "LOG: %s" "$*"
}

separator() {
	local char="${1:-'-'}"
	local width="${2:-$TERMINAL_WIDTH}"
	local line

	# Account for comment start sequence
	width=$(( width - 3 ))
	line="$(printf "%*s" "$width" "")"
	line="${line// /$char}"
	printf -- "-- %s\n" "$line"
}


#
# args
#

_usage() {
	cat <<EOF
Usage: $LIB_NAME [--width <terminal width>] <database file>

Text preview of SQLite databases. Requires \`sqlite3\` and \`bat\`.
EOF
}

declare -A _args=(
	['-h|--help']="ARG_HELP"
	['--width:']="ARG_WIDTH"
	['--']="ARGS"
)
parse_args _args "$@" || usage "Invalid arguments"

case "${#ARGS[@]}" in
1)
	DB_FILE="${ARGS[0]}"
	;;
*)
	usage "Expected 1 positional argument, got ${#ARGS[@]}"
	;;
esac

if [[ $ARG_WIDTH ]]; then
	TERMINAL_WIDTH="$ARG_WIDTH"
elif [[ -t 1 ]]; then
	TERMINAL_WIDTH=$(tput cols)
else
	usage "--width not specified and not on a terminal"
fi


#
# main
#

# Redirect everything to `bat` for syntax highlighting
# TODO: teach bat to accept an override for the file size (e.g. `--file-size=`),
#       then add `--style=header-filesize`
exec > >(bat \
	--file-name="$DB_FILE" \
	--language=sql \
	--style=grid,numbers,header-filename \
	--color=always \
	--paging=never \
	--wrap=auto \
	${TERMINAL_WIDTH:+--terminal-width="$TERMINAL_WIDTH"} \
)

# Account for decorations drawn by bat
# NB: this assumes max line number length is 4 digits (which is what bat hardcodes anyway)
TERMINAL_WIDTH=$(( TERMINAL_WIDTH - 7 ))

# Redirect unhandled stderr to keep the overall output of this script valid SQL
exec 2> >(emit_stderr)

if ! [[ -f "$DB_FILE" ]]; then
	emit "Error: file does not exist: ${DB_FILE@Q}"
	exit 1
fi

# Start sqlite3 as a coprocess for a single connection
coproc SQLITE { exec sqlite3 "$DB_FILE"; }

cleanup() {
	if [[ -n "${SQLITE_PID:-}" ]] && kill -0 "$SQLITE_PID" 2>/dev/null; then
		echo ".quit" >&"${SQLITE[1]}" 2>/dev/null
		wait "$SQLITE_PID" 2>/dev/null
	fi
}
trap cleanup EXIT

# Execute a command and capture output using a unique marker
sqlite_exec() {
	local marker="__END_${RANDOM}_${RANDOM}__"
	printf '%s\n' "$@" >&"${SQLITE[1]}"
	printf '.print %s\n' "$marker" >&"${SQLITE[1]}"
	while IFS= read -r line <&"${SQLITE[0]}"; do
		[[ "$line" == "$marker" ]] && return
		printf '%s\n' "$line"
	done
}

# Set consistent output settings
sqlite_exec \
	".headers off" \
	".mode list" \
	".separator '|'" \
	# EOL

# Header (not needed, taken care of by `bat`)
# separator "="
# emit "SQLite Database Preview: $DB_FILE"
# separator "="
# echo ""

# Get all table names (excluding internal sqlite_ tables)
# XXX: normally, we'd use a `| readarray` with lastpipe which has better error handling,
# but file descriptors of coprocesses are not preserved in subshells (except process/command substitutions)
readarray -t tables < <(
	sqlite_exec "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name;"
)

if [[ ! "${tables+set}" ]]; then
	emit "(No tables found)"
	exit 0
fi

separator '='
emit "Tables:"
for t in "${tables[@]}"; do
	emit "  $t"
done
separator '='
echo ""

# Process each table
for table in "${tables[@]}"; do
	[[ -z "$table" ]] && continue

	# Schema (valid DDL)
	separator '-'
	sqlite_exec ".schema \"$table\""

	# Columns summary
	separator '-'
	emit "Columns:"
	while IFS='|' read -r cid name type notnull dflt pk; do
		[[ -z "$cid" ]] && continue
		constraints=""
		[[ "$notnull" == "1" ]] && constraints+=" NOT NULL"
		[[ -n "$dflt" ]] && constraints+=" DEFAULT $dflt"
		[[ "$pk" == "1" ]] && constraints+=" PRIMARY KEY"
		emitf '  %-24s %s%s' "$name" "$type" "$constraints"
	done < <(
		sqlite_exec "PRAGMA table_info(\"$table\");"
	)

	# Row count and sample
	separator '-'
	emit "Rows:"
	count=$(sqlite_exec "SELECT COUNT(*) FROM \"$table\";")
	if (( count )); then
		# TODO: perhaps random sample?
		query="SELECT * FROM \"$table\" LIMIT 5;"

		# SQLite pretty-printing formats do not support limiting
		# overall width of the output, only per-column width.
		# Try to approximate a per-column width limit.

		sample_json="$(
			sqlite_exec \
				".mode json" \
				"$query"
		)"

		# shellcheck disable=SC2016
		WIDTHS_SORTED_JQ='.
			| (.[0] | keys) as $keys
			| map(map_values(tostring)) as $items
			| ($keys
				| map(. as $key
					| [$key] + ($items | map(.[$key]))
					| map(length)
					| max
				)
			)
			| sort
			| .[]
		'

		readarray -t widths < <(
			jq -r "$WIDTHS_SORTED_JQ" <<<"$sample_json"
		)
		n_columns="${#widths[@]}"

		# Table formatting overhead:
		# (2c padding + 1c leading separator) per column + 1c trailing separator + 3c comment start sequence + 2c outer padding
		width_overhead=$(( n_columns * 3 + 1 + 5 ))

		# Compute optimal per-column width limit using "water-filling" algorithm.
		# The idea: columns narrower than an equal share "give back" their unused
		# space to wider columns. We iteratively lock in narrow columns at their
		# natural width and redistribute remaining space among wider columns.

		available_width=$(( TERMINAL_WIDTH - width_overhead ))
		remaining_width=$available_width
		remaining_cols=$n_columns

		for w in "${widths[@]}"; do
			if (( remaining_cols == 0 )); then
				break
			fi
			# Tentative equal distribution among remaining columns
			tentative=$(( remaining_width / remaining_cols ))

			if (( w <= tentative )); then
				# This column fits within equal share, lock it at natural width
				remaining_width=$(( remaining_width - w ))
				(( remaining_cols-- ))
			else
				# This and all wider columns need to be capped
				break
			fi
		done

		if (( remaining_cols > 0 )); then
			max_col_width=$(( remaining_width / remaining_cols ))
		else
			# All columns fit naturally within available width, no wrapping needed
			max_col_width=
		fi

		emit "  Count: $count"
		emit "  Sample (LIMIT 5):"
		# XXX: for some reason, SQLite insists on wrapping columns even if --wrap is not set,
		#      thus set it explicitly to the maximum column width if wrapping is not required
		sqlite_exec \
			".headers on" \
			".mode box --wrap ${max_col_width:-${widths[-1]}}" \
			# EOL
		readarray -t sample_lines < <(
			sqlite_exec "$query"
		)
		sqlite_exec \
			".headers off" \
			".mode list" \
			".separator '|'" \
			# EOL
		emitf "  %s" "${sample_lines[@]}"
	else
		emit "  (empty table)"
	fi
	separator '-'
	echo ""
done
