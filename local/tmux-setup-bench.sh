#!/bin/bash -ex

# tmux in linux kernel console with ter-v14n @ 1920x1080
tmux set-option default-size 240x76

# create new windows
~/bin/local/tmux-ryzen-dashboard-bench.sh

# destroy the automatically created window with a shell
tmux kill-window -t @0
