#!/bin/bash

set -eo pipefail
shopt -s lastpipe


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
# main
#

if [[ -t 1 ]]; then
	TERMINAL_WIDTH=$(tput cols)
fi

# FIXME: proper argument parsing
if [[ $1 == --width ]]; then
	TERMINAL_WIDTH="$2"
	shift 2
fi

DB_FILE="$1"

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
		emit "  Count: $count"
		emit "  Sample (LIMIT 5):"
		sqlite_exec \
			".headers on" \
			".mode box" \
			# EOL
		readarray -t sample_lines < <(
			sqlite_exec "SELECT * FROM \"$table\" LIMIT 5;"
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
