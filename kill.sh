#!/bin/zsh

source reademacsvar.sh

if [ -n "$EMACS_PID" ]; then
    $EMACS_CLIENT_CMD -a '' -e '(kill-emacs)'
fi
