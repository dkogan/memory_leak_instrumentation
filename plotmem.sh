#!/bin/zsh

source reademacsvar.sh

while (true) { ps -h -p $EMACS_PID -O rss; sleep 1 } | awk '{print $2; fflush();}' | tee /tmp/memory.tmp.log | feedgnuplot --stream --lines
