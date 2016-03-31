#!/bin/zsh

source reademacsvar.sh

# t is the first argument, if given, otherwise 20. This is the timeout, in seconds
t=${1:-20}

sudo timeout $t perf record ${=RECORD_OPTS} -g --call-graph=fp -p ${EMACS_PID} -e 'probe_libc:*'
