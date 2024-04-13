#!/bin/bash -e

#
# tmux-ryzen-dashboard-bench.sh -- spawns a new tmux window with a stress test
#                                  and `ryzen_monitor` + `liquidctl` in watch(1)
#                                  in separate panes.
#
# ---------------------------------------
# |               |         |           |
# |               |         |           |
# |               |         |           |
# | ryzen_monitor |  bench  | liquidctl |
# |               |         |           |
# |               |         |           |
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

tmux resize-pane -t $pane_ryzen -x 100  # exact=98
tmux resize-pane -t $pane_liquidctl -x 55  # exact=52
tmux set-option -t $pane_shell remain-on-exit on
tmux respawn-pane -t $pane_shell -k "./bench.sh"
tmux select-pane -t $pane_shell
tmux bind-key R respawn-pane
