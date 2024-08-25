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
SCRIPT_DIR="${BASH_SOURCE%/*}"
respawn_helper="$SCRIPT_DIR/../misc/tmux-respawn-helper"

if [[ -e bench.sh ]]; then
  bench_cmd1=(sleep infinity)
  bench_cmd2=("$PWD/bench.sh")
else
  bench_cmd1=()
  bench_cmd2=()
fi

pane_shell=$(tmux new-window -P -F '#{pane_id}' -d -n "(bench)" \
  -- "${bench_cmd1[@]}")
pane_ryzen=$(tmux split-window -P -F '#{pane_id}' -t $pane_shell -h -b \
  -- "$respawn_helper" sudo ryzen_monitor)
pane_liquidctl=$(tmux split-window -P -F '#{pane_id}' -t $pane_shell -h \
  -- "$respawn_helper" sudo watch -n1 "liquidctl status")

tmux resize-pane -t $pane_ryzen -x 100  # exact=98
tmux resize-pane -t $pane_liquidctl -x 55  # exact=52
tmux set-option -t $pane_shell remain-on-exit on
if [[ ${bench_cmd2} ]]; then
  tmux respawn-pane -t $pane_shell -k "${bench_cmd2[@]}"
fi
tmux select-pane -t $pane_shell
tmux bind-key R respawn-pane
tmux bind-key '0' resize-pane -t $pane_ryzen -x 100 \\\; resize-pane -t $pane_liquidctl -x 55 \\\; select-pane -t $pane_shell
