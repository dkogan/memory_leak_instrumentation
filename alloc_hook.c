/*
  This is an LD_PRELOAD hook to log all allocation/deallocation operations. This
  lets me get malloc() entry and exit results with a single tracepoint and thus
  a single backtrace. Thus I can cut down the number of tracepoints I need in
  half without touching perf.

  Build with:

    gcc -o alloc_caching_hook.so -fpic -shared alloc_caching_hook.c -ldl

  Then run with

    LD_PRELOAD=./alloc_caching_hook.so program arg1 arg2
 */




#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <inttypes.h>
#include <stdbool.h>
#include <execinfo.h>

#include <unistd.h>
#include <malloc.h>

#include <dlfcn.h>

typedef void *(*malloc_t        )(size_t size);
typedef void *(*calloc_t        )(size_t nmemb, size_t size);
typedef void *(*realloc_t       )(void *ptr, size_t size);
typedef int   (*posix_memalign_t)(void **memptr, size_t alignment, size_t size);
typedef void *(*aligned_alloc_t )(size_t alignment, size_t size);
typedef void *(*valloc_t        )(size_t size);
typedef void *(*memalign_t      )(size_t alignment, size_t size);
typedef void *(*pvalloc_t       )(size_t size);
typedef void  (*free_t          )(void *ptr);


static void* report(int64_t arg1, int64_t arg2, int64_t ret, const char* func)
{
    // are we recursing? If so, don't report anything
    static bool in_report = false;
    if(in_report)
        return (void*)ret;


    in_report = true;

    fprintf(stderr, "%s(%#"PRIx64", %#"PRIx64" -> %#"PRIx64"\n", func, arg1, arg2, ret);

    // report backtrace
    {
        void* callstack_addrs[20];
        int depth = backtrace(callstack_addrs, sizeof(callstack_addrs)/sizeof(callstack_addrs[0]));

        char** callstack_strs = backtrace_symbols(callstack_addrs, depth);
        for(int i=0; i<depth; i++)
            fprintf(stderr, "  %s\n", callstack_strs[i]);
        free(callstack_strs);
    }

    in_report = false;

    return (void*)ret;
}

#define say(fmt, ...) do { fprintf(stderr, fmt, ##__VA_ARGS__); } while(0)
#define die(fmt, ...) do { fprintf(stderr, fmt, ##__VA_ARGS__); exit(1); } while(0)


static void _header(void** orig, int* initializing, const char* func)
{
    if( *orig == NULL )
    {
        *initializing = 1;

        *orig = dlsym( RTLD_NEXT, func );
        if( *orig == NULL )
        {
            die("No original %s() function\n", func);
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



void *malloc(size_t size)
{
    HEADER(malloc);
    return report((int64_t)size, -1, (int64_t)orig(size), __func__);
}

void *calloc(size_t nmemb, size_t size)
{
    HEADER(calloc);
    return report((int64_t)nmemb, (int64_t)size, (int64_t)orig(nmemb, size), __func__);
}

void *realloc(void *ptr, size_t size)
{
    HEADER(realloc);
    return report((int64_t)ptr, (int64_t)size, (int64_t)orig(ptr, size), __func__);
}

int   posix_memalign(void **memptr, size_t alignment, size_t size)
{
    say("%s UNTRACED\n", __func__);
    return -1;
}

void *aligned_alloc(size_t alignment, size_t size)
{
    say("%s UNTRACED\n", __func__);
    return NULL;
}

void *valloc(size_t size)
{
    say("%s UNTRACED\n", __func__);
    return NULL;
}

void *memalign(size_t alignment, size_t size)
{
    say("%s UNTRACED\n", __func__);
    return NULL;
}

void *pvalloc(size_t size)
{
    say("%s UNTRACED\n", __func__);
    return NULL;
}

void free(void *ptr)
{
    HEADER(free);
    orig(ptr);

    report((int64_t)ptr, -1, -1, __func__);
}
