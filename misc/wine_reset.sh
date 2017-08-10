function assert() {
	if ! eval "[[ $* ]]"; then
		echo "- Assertion failed: '$*'. Exiting." >&2
		exit 1
	fi
}

function assert_no_wine_dir() {
	assert '! -e "$HOME/.wine"'
}

function reset_wine() {
	echo "- Re-creating WINE profile at '$WINE_PROFILE'"
	rm -rf "$WINE_PROFILE"
	assert_no_wine_dir
	WINEARCH=win32 wineboot &>/dev/null
	wineserver -k

	if [[ ! -e "$WINE_PROFILE" ]]; then
		mv "$HOME/.wine" "$WINE_PROFILE"
	fi
}

echo "- Stopping WINE..." >&2

wineserver -k
if pgrep wineserver; then
	echo "Could not kill WINE. Aborting." >&2
	exit 1
fi

if [[ -L "$HOME/.wine" ]]; then
	WINE_PROFILE="$(realpath "$HOME/.wine")"
	WINE_LINK="$(readlink "$HOME/.wine")"
	rm -f "$HOME/.wine"

	echo "- WINE profile points to '$WINE_PROFILE'."
	if [[ "$WINE_PROFILE" != "$WINE_LINK" ]]; then
		echo "- WINE profile link points to '$WINE_LINK'."
	fi

	reset_wine

	echo "- Restoring profile link to '$WINE_LINK'."
	assert_no_wine_dir
	ln -s "$WINE_LINK" "$HOME/.wine"
else
	WINE_PROFILE="$HOME/.wine"

	echo "- WINE profile is stored in-place."

	reset_wine
fi

