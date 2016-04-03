#!/bin/zsh

source reademacsvar.sh

ps -h -p $EMACS_PID -O rss  | awk '{print $2}'
