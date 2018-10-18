#!/bin/bash

#
# tmux-dashboard.sh -- spawns a new tmux window with `stern`, `kubectl top pods`
#                      and `kubectl get pods` in watch(1) for a given selector.
#
# ----------------------- 
# |          |          |
# | get pods | top pods |
# |          |          |
# |---------------------|
# |                     |
# |       stern         |
# |                     |
# -----------------------
#

set -e

SELECTOR=( "$@" )

pane_stern=$(tmux new-window -P -F '#{pane_id}' -d -n "(k8s: ${SELECTOR[*]})" \
  -- stern "${SELECTOR[@]}")
pane_toppods=$(tmux split-window -P -F '#{pane_id}' -t $pane_stern -v -b \
  -- watch -n30 kubectl top pods "${SELECTOR[@]}")
pane_getpods=$(tmux split-window -P -F '#{pane_id}' -t $pane_toppods -h -b \
  -- watch -n5 kubectl get pods "${SELECTOR[@]}")

