#!/bin/zsh

# EMACS_PID must be given in the environment, or we'll infer it
test -n "$EMACS_PID" || source reademacsvar.sh

before=`./show_daemon_usage.sh`
gdb --batch-silent --eval-command 'print malloc_trim(0)' -p $EMACS_PID
after=`./show_daemon_usage.sh`

echo "before: $before"
echo "after: $after"
echo "freed: $(($before - $after))"
