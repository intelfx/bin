#!/bin/bash -ex

# double nested tmux in gnome-terminal in gnome-shell on 2560x1440 at Iosevka@9
#tmux set-option default-size 213x37
# double nested tmux in gnome-terminal in gnome-shell on 2560x1440 at Iosevka@8
#tmux set-option default-size 255x40
# double nested tmux in gnome-terminal in gnome-shell on 2560x1440 at Iosevka@9 at 90%
tmux set-option default-size 255x47

respawn_helper="$HOME/bin/misc/tmux-respawn-helper"

# create new windows
tmux new-window -n "(htop)" \
  -- "$respawn_helper" sudo htop
~/bin/local/tmux-ryzen-dashboard.sh

# destroy the automatically created window with a shell
tmux kill-window -t @0
