#!/bin/zsh

source reademacsvar.sh

while (true) { ps -h -p $EMACS_PID -O rss; usleep 250000 } | awk '{print NR/4.,$2; fflush();}' | tee /tmp/memory.tmp.log | feedgnuplot --stream --lines --domain
