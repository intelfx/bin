#!/bin/bash

vncviewer -FullScreen -PasswordFile=$HOME/.vnc/passwd -PreferredEncoding=Hextile -NoJPEG -MenuKey=Pause "$@"
