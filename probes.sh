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

    perf probe -x /usr/lib/x86_64-linux-gnu/libXft.so --add XftFontOpenInfo
    perf probe -x /usr/lib/x86_64-linux-gnu/libXft.so --add 'XftFontOpenInfo_ref1=XftFontOpenInfo:126 font'
    perf probe -x /usr/lib/x86_64-linux-gnu/libXft.so --add 'XftFontOpenInfo_cached=XftFontOpenInfo:31 font font->ref info->num_unref_fonts'
    perf probe -x /usr/lib/x86_64-linux-gnu/libXft.so --add 'XftFontClose:5 font font->ref'
    perf probe -x /usr/lib/x86_64-linux-gnu/libXft.so --add XftFontCopy
    perf probe -x /usr/lib/x86_64-linux-gnu/libXft.so --add XftFontDestroy
    perf probe -x /usr/lib/x86_64-linux-gnu/libXft.so --add XftFontManageMemory
    perf probe -x /usr/lib/x86_64-linux-gnu/libXft.so --add 'XftFontManageMemory_ret=XftFontManageMemory%return'
    perf probe -x /usr/lib/x86_64-linux-gnu/libXft.so --add 'XftFontManageMemory_info=XftFontManageMemory:9 info->num_unref_fonts'

    perf probe -x $EMACS_CMD --add 'added_cache=font_matching_entity:35'
    perf probe -x $EMACS_CMD --add 'added_cache2=font_list_entities:50'


# perf probe -x /usr/lib/x86_64-linux-gnu/libXt.so --add XtCloseDisplay

    # perf probe -x $EMACS_CMD --add xftfont_open
    # perf probe -x $EMACS_CMD --add xftfont_close
    # perf probe -x $EMACS_CMD --add delete_frame
    # perf probe -x $EMACS_CMD --add x_delete_terminal
    # perf probe -x $EMACS_CMD --add 'x_delete_terminal_after_if=x_delete_terminal:9 dpyinfo->display'
    # perf probe -x $EMACS_CMD --add 'x_term_init'
    # perf probe -x $EMACS_CMD --add 'x_connection_closed error_message:string'

fi
