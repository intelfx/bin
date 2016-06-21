#!/bin/bash

# $1: whether to enable dark (1 or 0)
function adjust_gtk3() {
	git config --file="$HOME/.config/gtk-3.0/settings.ini" Settings.gtk-application-prefer-dark-theme "$1"
}

function adjust_gedit() {
	local scheme=( solarized-light solarized-dark )

	dconf write /org/gnome/gedit/preferences/editor/scheme "'${scheme[$1]}'"
}

function adjust_terminal() {
	local profiles_default=( 4b05dbdf-11e8-4f29-b788-7016ec6b6de9
	                         b739b980-6bbc-4e0c-9dda-313ad61029ff )
	dconf write /org/gnome/terminal/legacy/profiles:/default "'${profiles_default[$1]}'"
}

function adjust_builder() {
	local night_mode=( false true )
	local style_scheme_name=( solarized-light solarized-dark )

	dconf write /org/gnome/builder/night-mode "${night_mode[$1]}"
	dconf write /org/gnome/builder/editor/style-scheme-name "'${style_scheme_name[$1]}'"
}

function adjust_kde() {
	local kdeglobals=( light dark )
	local config_path="$(systemd-path user-configuration)"

	cp -a "$config_path/kdeglobals-${kdeglobals[$1]}" "$config_path/kdeglobals"
	kbuildsycoca5
}

function adjust_kate() {
	local schema=( "Solarized (light)" "Solarized (dark)" )
	local config_path="$(systemd-path user-configuration)/katepartrc"

	sed -re "s|^Schema=.*|Schema=${schema[$1]}|" -i "$config_path"
}

case "${1:-1}" in
	dark|on|1) set -- 1 ;;
	light|off|0) set -- 0 ;;
	*) echo "E: unknown mode: '$1'" >&2; exit 1 ;;
esac

adjust_gtk3 "$@"
adjust_gedit "$@"
adjust_terminal "$@"
adjust_kde "$@"
adjust_kate "$@"
