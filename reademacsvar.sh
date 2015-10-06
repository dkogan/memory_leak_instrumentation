#!/bin/zsh

EMACS_CLIENT_CMD=/tmp/emacsclient-tst
EMACS_CMD=/tmp/emacs-tst
EMACS_PID=`pidof ${EMACS_CMD:t}`

# Used by emacs for its daemon pipe. I override this here so that I can have an
# emacs daemon session I'm using to do work at the same time as another daemon
# session I'm using to test stuff
export TMPDIR=/tmp/emacstest 

# Some options for 'perf record'
RECORD_OPTS='-m512 -r50'

