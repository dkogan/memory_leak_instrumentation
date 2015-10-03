#!/bin/zsh

source reademacsvar.sh

sudo perf record ${=RECORD_OPTS} -g --call-graph=fp -p ${EMACS_PID} -eprobe_libc:{free,{malloc,calloc,realloc}{,_ret}} -eprobe_libc:aligned_alloc{,_1,_ret} -eprobe_libc:posix_memalign{,_ret}
