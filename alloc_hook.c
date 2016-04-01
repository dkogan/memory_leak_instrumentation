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

#define UNW_LOCAL_ONLY
#include <libunwind.h>

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


#define say(fmt, ...) do { if(!fp) initfp(); fprintf(fp,     fmt, ##__VA_ARGS__); } while(0)
#define die(fmt, ...) do { fprintf(stderr, fmt, ##__VA_ARGS__); exit(1); } while(0)

static FILE* fp = NULL;
static bool recursing_initfp = false;
static bool recursing_report = false;

static void initfp(void)
{
    recursing_initfp = true;

    fp = fopen("/tmp/log", "w");

    recursing_initfp = false;
}

static void* report(int64_t arg1, int64_t arg2, int64_t ret, const char* func)
{
    // are we recursing? If so, don't report anything
    if(recursing_initfp || recursing_report)
        return (void*)ret;

    recursing_report = true;

    say( "%s(%#"PRIx64", %#"PRIx64") -> %#"PRIx64"\n", func, arg1, arg2, ret);

    // report backtrace
    {
        unw_cursor_t cursor;
        unw_context_t uc;
        unw_word_t ip, offp;
        char name[256] = {'\0'};

        unw_getcontext(&uc);
        unw_init_local(&cursor, &uc);
        while (unw_step(&cursor) > 0 &&
               !unw_get_proc_name (&cursor, name, sizeof(name), &offp) )
        {

            unw_get_reg(&cursor, UNW_REG_IP, &ip);
            say( "  %s [%p]\n", name, (void*)ip);
            name[0] = '\0';
        }
        say("\n");
    }

    recursing_report = false;

    return (void*)ret;
}


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
