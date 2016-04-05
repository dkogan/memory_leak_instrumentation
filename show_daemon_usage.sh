#!/bin/zsh

# EMACS_PID must be given in the environment, or we'll infer it
test -n "$EMACS_PID" || source reademacsvar.sh

ps -h -p $EMACS_PID -O rss  | awk '{print $2}'
