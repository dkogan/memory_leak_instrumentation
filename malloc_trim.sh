#!/bin/zsh

source reademacsvar.sh
gdb --batch-silent --eval-command 'print malloc_trim(0)' -p $EMACS_PID
