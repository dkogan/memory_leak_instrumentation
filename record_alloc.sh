#!/bin/zsh

source reademacsvar.sh

# t is the first argument, if given, otherwise 20. This is the timeout, in seconds
t=${1:-20}

sudo timeout $t perf record ${=RECORD_OPTS} -g --call-graph=fp -p ${EMACS_PID} -eprobe_libc:{free,{malloc,calloc,realloc}{,_ret}} -eprobe_libc:aligned_alloc{,_1,_ret} -eprobe_libc:posix_memalign{,_ret}
