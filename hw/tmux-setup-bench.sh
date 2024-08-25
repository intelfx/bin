#!/bin/bash -ex

cd "$HOME"
SCRIPT_DIR="${BASH_SOURCE%/*}"
respawn_helper="$SCRIPT_DIR/../misc/tmux-respawn-helper"

# tmux in linux kernel console with ter-v14n @ 1920x1080
tmux set-option default-size 240x76

# create new windows
tmux new-window -n "(htop)" \
  -- "$respawn_helper" sudo htop
$SCRIPT_DIR/tmux-ryzen-dashboard-bench.sh

# destroy the automatically created window with a shell
tmux kill-window -t @0
