#!/bin/bash -e

#
# tmux-ryzen-dashboard.sh -- spawns a new tmux window with `ryzen_monitor`,
#                            `sensors` and `liquidctl` in watch(1) and a shell.
#
# ---------------------------------------
# |               |         |           |
# |               | sensors |           |
# |               |         |           |
# | ryzen_monitor |---------| liquidctl |
# |               |         |           |
# |               |  shell  |           |
# |               |         |           |
# ---------------------------------------
#

cd "$HOME"

pane_shell=$(tmux new-window -P -F '#{pane_id}' -d -n "(dashboard)" \
  )
pane_ryzen=$(tmux split-window -P -F '#{pane_id}' -t $pane_shell -h -b \
  -- sudo ryzen_monitor)
pane_liquidctl=$(tmux split-window -P -F '#{pane_id}' -t $pane_shell -h \
  -- sudo watch -n1 "liquidctl status")
pane_sensors=$(tmux split-window -P -F '#{pane_id}' -t $pane_shell -v -b \
  -- watch -n1 "sensors 'nct6798-*' 'nvme-*' 'drivetemp-*'")

tmux resize-pane -t $pane_ryzen -x 100  # exact=98
tmux resize-pane -t $pane_liquidctl -x 55  # exact=52
tmux resize-pane -t $pane_shell -y '25%'
