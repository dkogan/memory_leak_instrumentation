/*
  This is an LD_PRELOAD hook to log all allocation/deallocation operations. It
  is simple, and doesn't even try to output a backtrace. I don't currently use
  this for my emacs work, but it might be useful later.

  Build with:

    gcc -o alloc_hook.so -fpic -shared alloc_hook.c

  Then run with

    LD_PRELOAD=./alloc_hook.so program arg1 arg2
 */




#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>

#include <unistd.h>
#include <malloc.h>

#include <dlfcn.h>

typedef ssize_t (*read_t)(int fd, void *buf, size_t count);



typedef void *(*malloc_t        )(size_t size);
typedef void *(*calloc_t        )(size_t nmemb, size_t size);
typedef void *(*realloc_t       )(void *ptr, size_t size);
typedef int   (*posix_memalign_t)(void **memptr, size_t alignment, size_t size);
typedef void *(*aligned_alloc_t )(size_t alignment, size_t size);
typedef void *(*valloc_t        )(size_t size);
typedef void *(*memalign_t      )(size_t alignment, size_t size);
typedef void *(*pvalloc_t       )(size_t size);
typedef void  (*free_t          )(void *ptr);



static FILE* fp = NULL;


#define say(fmt, ...) do { if(fp) fprintf(fp, fmt, ##__VA_ARGS__); } while(0)


static void _header(void** orig, int* initializing, const char* func)
{
    if( *orig == NULL )
    {
        *initializing = 1;

        *orig = dlsym( RTLD_NEXT, func );
        if( *orig == NULL )
        {
            fprintf(stderr, "No original %s() function\n", func);
            exit(1);
        }

        *initializing = 0;
    }

    if( fp == NULL )
    {
        *initializing = 1;

        fp = fopen("/tmp/alloc_hook.log", "w");
        if(fp == NULL)
        {
            fprintf(stderr, "Couldn't open log\n");
            exit(1);
        }

        *initializing = 0;
    }
}
#define HEADER(func)                                            \
    /* the the original function so that I can call it */       \
    static int initializing = 0;                                \
    static func ## _t orig;                                     \
    if( !initializing )                                         \
        _header((void**)&orig, &initializing, #func)



extern void*__libc_malloc(size_t size);
void *malloc(size_t size)
{
    HEADER(malloc);

    // the libc machinery I use during init time needs a malloc, so I use the
    // internal one to avoid a loop
    if(initializing)
        return (void*)__libc_malloc(size);

    say("probe_libc:malloc: bytes=%#zx\n", size);
    void* out = orig(size);
    say("probe_libc:malloc_ret: arg1=%#x\n", out);
    return out;
}

extern void* __libc_calloc(size_t nmemb, size_t size);
void *calloc(size_t nmemb, size_t size)
{
    HEADER(calloc);

    // the libc machinery I use during init time needs a malloc, so I use the
    // internal one to avoid a loop
    if(initializing)
        return (void*)__libc_calloc(nmemb, size);

    say("probe_libc:calloc: elem_size=%#zx n=%#zx \n", size, nmemb);
    void* out = orig(nmemb, size);
    say("probe_libc:calloc_ret: arg1=%#x\n", out);
    return out;
}

void *realloc(void *ptr, size_t size)
{
    HEADER(realloc);

    say("probe_libc:realloc: oldmem=%#x bytes=%#zx \n", ptr, size);
    void* out = orig(ptr, size);
    say("probe_libc:realloc_ret: arg1=%#x\n", out);
    return out;
}
int   posix_memalign(void **memptr, size_t alignment, size_t size)
{
    HEADER(posix_memalign);
    say("posix_memalign UNTRACED\n");
    return orig(memptr, alignment, size);
}
void *aligned_alloc(size_t alignment, size_t size)
{
    HEADER(aligned_alloc);
    say("aligned_alloc UNTRACED\n");
    return orig(alignment, size);
}
void *valloc(size_t size)
{
    HEADER(valloc);
    say("valloc UNTRACED\n");
    return orig(size);
}
void *memalign(size_t alignment, size_t size)
{
    HEADER(memalign);
    say("memalign UNTRACED\n");
    return orig(alignment, size);
}
void *pvalloc(size_t size)
{
    HEADER(pvalloc);
    say("pvalloc UNTRACED\n");
    return orig(size);
}
void free(void *ptr)
{
    HEADER(free);
    say("probe_libc:free: mem=%#x\n", ptr);
    return orig(ptr);
}
