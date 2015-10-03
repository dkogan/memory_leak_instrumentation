#!/bin/zsh

EMACS_CLIENT_CMD=/tmp/emacsclient-tst
EMACS_CMD=/tmp/emacs-tst
EMACS_PID=`pidof ${EMACS_CMD:t}`

RECORD_OPTS=-m512 -r50

export TMPDIR=/tmp/emacstest 
