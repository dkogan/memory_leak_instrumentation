#!/bin/zsh

set -e -x

if [ `whoami` != "root" ]; then
    sudo $0
else

    source ${0:h}/reademacsvar.sh

    perf probe --del '*'
    perf probe -x /lib/x86_64-linux-gnu/libc-2.19.so --add 'malloc=malloc bytes'
    perf probe -x /lib/x86_64-linux-gnu/libc-2.19.so --add 'malloc_ret=malloc%return $retval'
    perf probe -x /lib/x86_64-linux-gnu/libc-2.19.so --add 'calloc=calloc elem_size n'
    perf probe -x /lib/x86_64-linux-gnu/libc-2.19.so --add 'calloc_ret=calloc%return $retval'
    perf probe -x /lib/x86_64-linux-gnu/libc-2.19.so --add 'realloc=realloc oldmem bytes'
    perf probe -x /lib/x86_64-linux-gnu/libc-2.19.so --add 'realloc_ret=realloc%return $retval'
    perf probe -x /lib/x86_64-linux-gnu/libc-2.19.so --add 'aligned_alloc alignment bytes'
    perf probe -x /lib/x86_64-linux-gnu/libc-2.19.so --add 'aligned_alloc_ret=aligned_alloc%return $retval'
    perf probe -x /lib/x86_64-linux-gnu/libc-2.19.so --add 'posix_memalign alignment size'
    perf probe -x /lib/x86_64-linux-gnu/libc-2.19.so --add 'posix_memalign_ret=posix_memalign%return $retval'
    perf probe -x /lib/x86_64-linux-gnu/libc-2.19.so --add 'free mem'
fi
