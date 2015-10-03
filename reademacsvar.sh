#!/bin/zsh

EMACS_CLIENT_CMD=/tmp/emacsclient-tst
EMACS_CMD=/tmp/emacs-tst
EMACS_PID=`pidof ${EMACS_CMD:t}`


export TMPDIR=/tmp/emacstest 
