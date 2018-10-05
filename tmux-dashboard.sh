#!/bin/bash

SELECTOR=( "$@" )

set -e

pane_stern=$(tmux new-window -P -F '#{pane_id}' -d -n "(k8s: ${SELECTOR[*]})" \
  -- stern "${SELECTOR[@]}")
pane_toppods=$(tmux split-window -P -F '#{pane_id}' -t $pane_stern -v -b \
  -- watch -n1 kubectl top pods "${SELECTOR[@]}")
pane_getpods=$(tmux split-window -P -F '#{pane_id}' -t $pane_toppods -h -b \
  -- watch -n1 kubectl get pods "${SELECTOR[@]}")

