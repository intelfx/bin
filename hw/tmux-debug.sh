#!/bin/bash -ex

#
# -----------------------------------
# |           |         |   btrfs   |
# |           |         |  balance  |
# |           |         |  status   |
# |   dmesg   |  shell  |-----------|
# |           |         |   btrfs   |
# |           |         |    fi     |
# |           |         |   usage   |
# -----------------------------------
#

cd "$HOME"

pane_shell=$(tmux new-window -P -F '#{pane_id}' -d -n "(shell)" \
  )
pane_dmesg=$(tmux split-window -P -F '#{pane_id}' -t $pane_shell -h -b \
  -- sudo dmesg -w)
pane_btrfs_usage=$(tmux split-window -P -F '#{pane_id}' -t $pane_shell -h \
  -- sudo watch -n1 btrfs fi usage /)
pane_btrfs_balance=$(tmux split-window -P -F '#{pane_id}' -t $pane_btrfs_usage -v -b \
  -- sudo watch -n1 btrfs balance status -v /)

tmux resize-pane -t $pane_dmesg -x 100
tmux resize-pane -t $pane_btrfs_usage -x 72
tmux resize-pane -t $pane_btrfs_balance -y 10
tmux select-pane -t $pane_shell
