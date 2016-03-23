#!/bin/zsh

EMACS_CLIENT_CMD_RAW=/home/dima/emacs/lib-src/emacsclient
EMACS_CMD_RAW=/home/dima/emacs/src/emacs
EMACS_CMD=${EMACS_CMD_RAW:h}/emacs-tst
EMACS_CLIENT_CMD=${EMACS_CLIENT_CMD_RAW:h}/emacsclient-tst
EMACS_PID=`pidof ${EMACS_CMD:t}`

# Used by emacs for its daemon pipe. I override this here so that I can have an
# emacs daemon session I'm using to do work at the same time as another daemon
# session I'm using to test stuff
export TMPDIR=/tmp/emacstest 

# Some options for 'perf record'
RECORD_OPTS='-m512 -r50'

test -e $EMACS_CMD        || ln -fs $EMACS_CMD_RAW        $EMACS_CMD
test -e $EMACS_CLIENT_CMD || ln -fs $EMACS_CLIENT_CMD_RAW $EMACS_CLIENT_CMD
