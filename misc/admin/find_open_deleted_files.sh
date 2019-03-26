#!/bin/bash

function suppress_filter() {
	case "$1" in
		"/SYSV"*) return 0 ;;
		"/memfd:"*) return 0 ;;
		"/drm mm object") return 0 ;;
		"/run/user/"*) return 0 ;;
		*"/dconf/user") return 0 ;;
		*"/gvfs-metadata/"*) return 0 ;;
		"/[aio]") return 0 ;;
		"/dev/zero") return 0 ;;
	esac

	return 1
}

declare -A SUPPRESS_COUNTER
declare -A SERVICE_COUNTER
declare -A SCOPE_COUNTER

function parse_file() {
	local NAME EXECUTABLE CGROUP
	declare -a SERVICE SCOPE

	if [[ "${CURRENT_FILE[type]}" == "DEL" ]]; then
		NAME="${CURRENT_FILE[name]}"

		if ! (( NO_SUPPRESS )) && suppress_filter "$NAME"; then
			(( ++SUPPRESS_COUNTER[$NAME] ))
			return
		fi

		EXECUTABLE="$(readlink "/proc/$CURRENT_PID/exe")"
		CGROUP="$(grep -F '.slice/' "/proc/$CURRENT_PID/cgroup" | head -n1)"
		readarray -t SERVICE < <(grep -Eo '[^/]*\.service' <<< "$CGROUP")
		readarray -t SCOPE < <(grep -Eo '[^/]*\.scope' <<< "$CGROUP")

		echo "PID $CURRENT_PID ($EXECUTABLE) (cgroup: $CGROUP) (services: ${SERVICE[*]}) (scopes: ${SCOPE[*]}) holds the deleted file \"${CURRENT_FILE[name]}\""

		if (( ${#SERVICE[@]} )); then
			(( ++SERVICE_COUNTER[${SERVICE[*]}] ))
		elif (( ${#SCOPE[@]} )); then
			(( ++SCOPE_COUNTER[${SCOPE[*]}] ))
		else
			(( ++OTHER_COUNTER ))
		fi


#		if [[ -e "${CURRENT_FILE[name]}" ]]; then
#
#			PACKAGE="$(pacman -Qqo "${CURRENT_FILE[name]}" 2>/dev/null)"
#			if [[ "$PACKAGE" ]]; then
#				echo "owned by '$PACKAGE'"
#			else
#				echo "not owned by any package"
#			fi
#		else
#			echo "(does not exist anymore)"
#		fi
	fi
}

#
# Motherfucking stateful lsof output.
#

declare -A CURRENT_FILE

while read -r line; do
	TYPE="${line:0:1}"
	VALUE="${line:1}"
	case "$TYPE" in
		p) CURRENT_PID="$VALUE" ;;
		n) CURRENT_FILE[name]="$VALUE" ;;
		f) parse_file; CURRENT_FILE=( [type]="$VALUE" ) ;;
		*) echo "E: unknown field type '$TYPE' value '$VALUE' in lsof output" >&2 ;;
	esac
done < <(lsof -F pfn)

parse_file # last one

echo ""
echo "Suppressed files:"

for name in "${!SUPPRESS_COUNTER[@]}"; do
	echo "File \"$name\" has been suppressed ${SUPPRESS_COUNTER[$name]} times"
done

echo ""
echo "Services to be restarted:"

for name in "${!SERVICE_COUNTER[@]}"; do
	echo "Processes of service \"$name\" hold ${SERVICE_COUNTER[$name]} deleted files"
done

echo ""
echo "Scopes to be restarted:"

for name in "${!SCOPE_COUNTER[@]}"; do
	echo "Processes of scope \"$name\" hold ${SCOPE_COUNTER[$name]} deleted files"
done

echo
echo "Non-grouped processes hold ${MISC_COUNTER:-0} deleted files"
