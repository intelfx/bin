#!/bin/bash
SAVE_PLACE="/usr/share/nethack/save/${UID}${USER}.gz"
SAVE_BACKUP="$HOME/tmp/nethack-save.gz"

if ! [[ -f "$SAVE_PLACE" ]]; then
	if [[ -f "$SAVE_BACKUP" ]]; then
		echo "---- No savefile in '$SAVE_PLACE' and backup exists. Restore?"
		read
		cp -p "$SAVE_BACKUP" "$SAVE_PLACE"
	else
		echo "==== No savefile in '$SAVE_PLACE' and no backup. Proceed as usual?"
		read
	fi
else
	echo "---- Savefile exists. Proceeding."
fi

nethack

if [[ -f "$SAVE_PLACE" ]]; then
	if [[ -f "$SAVE_BACKUP" ]]; then
		echo "---- Savefile exists and backup exists. Overwrite backup?"
		read
	else
		echo "---- Savefile exists and no backup. Overwriting."
	fi
	cp "$SAVE_PLACE" "$SAVE_BACKUP"
fi
