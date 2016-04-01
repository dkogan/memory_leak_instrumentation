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

//#define LIBUNWIND 1


#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <inttypes.h>
#include <stdbool.h>

#ifdef LIBUNWIND
  #define UNW_LOCAL_ONLY
  #include <libunwind.h>
#else
  #include <backtrace.h>
#endif

#include <unistd.h>
#include <malloc.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <string.h>
#include <time.h>

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


#define die(fmt, ...) do { fprintf(stderr, fmt, ##__VA_ARGS__); exit(1); } while(0)

static int fd = -1;
static char line[16384];
static int iline = 0;
static union
{
    int any;

    struct
    {
        int initfd : 1;
        int report : 1;
    };
} recursing = {};
static void initfd(void)
{
    recursing.initfd = true;

    char filename[128] = "/tmp/log-";
    sprintf(filename, "%s-%d", "/tmp/log", getpid());

    fd = open(filename, O_RDWR | O_CREAT | O_TRUNC, 0644);
    if( fd < 0 )
        die("Couldn't open file %s\n", "/tmp/log");

    void closefd(void)
    {
        close(fd);
    }
    atexit(&closefd);

    recursing.initfd = false;
}
static void _say_mem(const char* mem, int len)
{
    if(len > (int)sizeof(line) - iline) len = sizeof(line) - iline;
    memcpy(&line[iline], mem, len);
    iline += len;
}
static void say_mem(const char* mem, int len)
{
    if(fd < 0)
        initfd();

    _say_mem(mem, len);
}
static void say_string(const char* string)
{
    if(fd < 0)
        initfd();

    _say_mem(string, strlen(string));
}
static void _say_char(const char c)
{
    if( iline < (int)sizeof(line))
        line[iline++] = c;
}
static void say_char(const char c)
{
    if(fd < 0)
        initfd();
    _say_char(c);
}
static void say_hex64(uint64_t x)
{
    if(fd < 0)
        initfd();

    if( x == 0 )
        _say_char('0');
    else if( x+1 == 0)
        _say_mem("-1", 2);
    else
    {
        // skip leading 0s
        int i = 0;
        for(; i<16; i++, x <<= 4)
            if(x >> 60)
                break;

        for(; i<16; i++, x <<= 4)
        {

#define ascii_nibble(_n)                                \
            ({ unsigned char n = _n;                    \
                n <= 9 ? (n + '0') : (n - 10 + 'A'); })

            if( iline < (int)sizeof(line) )
                line[iline++] = ascii_nibble(x >> 60);
        }
    }
}

static void say_eol(void)
{
    if(fd < 0)
        initfd();

    if( iline < (int)sizeof(line))
        line[iline++] = '\n';
    write(fd, line, iline);
    iline = 0;
}



static int64_t gettime64(void)
{
    struct timespec timespec;
    clock_gettime( CLOCK_MONOTONIC, &timespec );
    return (int64_t)timespec.tv_sec*1000000LL + timespec.tv_nsec / 1000LL;
}

static void* report(int64_t arg1, int64_t arg2, int64_t ret, const char* func)
{
    // are we recursing? If so, don't report anything
    if(recursing.any)
        return (void*)ret;

    // Log data only between timestamps T0 and T1 (in seconds)
    #define T0 10
    #define T1 30
    static int64_t t0 = 0;
    if( t0 == 0 ) t0 = gettime64();
    int64_t trelative = gettime64() - t0;
    if( trelative < T0*1000000L || trelative > T1*1000000L )
        return (void*)ret;


    recursing.report = true;

    // I want to use printf... here, but something about the standard library is
    // interacting poorly with the overridden memory allocators (swallowed data
    // and/or lots of \0), so I do it myself
    // say( "%s(%#"PRIx64", %#"PRIx64") -> %#"PRIx64"\n", func, arg1, arg2, ret);

    say_string(func);
    say_char('(');
    say_hex64(arg1);
    say_string(", ");
    say_hex64(arg2);
    say_string(") -> ");
    say_hex64(ret);
    say_char('\n');

    // report backtrace
    {
#ifdef LIBUNWIND
  #if 1
        // slower than the other option. See comment below
        unw_cursor_t cursor;
        unw_context_t uc;
        unw_word_t ip, offp;
        char name[256] = {'\0'};


        void* ips[20];
        int depth = sizeof(ips)/sizeof(ips[0]);

        unw_getcontext(&uc);
        unw_init_local(&cursor, &uc);

        while (unw_step(&cursor) > 0 &&
                !unw_get_proc_name (&cursor, name, sizeof(name), &offp))
        {
            unw_get_reg(&cursor, UNW_REG_IP, &ip);
            say_string( "  " );
            say_string(name);
            say_string('\n');

            name[0] = '\0';
        }
  #else
        // much faster than above event if we didn't pull out the function
        // names. But here the details are internal to the function, so we can't
        // pull the function names even if we wanted to. AND unw_backtrace()
        // uses an unexported function internally, so we can't do anything here
        // without rebuilding libunwind
        void* ips[20];
        int LEN_IPS = sizeof(ips)/sizeof(ips[0]);
        unw_backtrace(ips, LEN_IPS);

        for(int i=0; i<LEN_IPS && ips[i]; i++)
        {
            say_string("  [");
            say_hex64((uint64_t)ips[i]);
            say_string("]\n");
        }
  #endif
#else
        // libbacktrace. A bit slower than libunwind, maybe. But function name
        // lookup works much better
        void error_callback(void *data __attribute__((unused)),
                            const char *msg,
                            int errnum)
        {
            if(fd < 0)
                initfd();

            fprintf(stderr, "libbacktrace error: '%s'\n", msg);
        }

        static struct backtrace_state* state = NULL;
        if( !state )
            state =
                backtrace_create_state( "/tmp/emacs-tst", 0, error_callback, NULL );

        int count = 0;

  #if 0
        int simple_callback(void *data __attribute__((unused)),
                            uintptr_t pc)
        {
            say_string("  [");
            say_hex64((uint64_t)pc);
            say_string("]\n");
            return !(count++ < 10 && pc != 0 && 1+(uint64_t)pc != 0);
        }
        backtrace_simple (state, 1, &simple_callback, &error_callback, NULL);
  #else
        int full_callback(void *data __attribute__((unused)),
                          uintptr_t pc,
                          const char *filename, int lineno,
                          const char *function)
        {
            if( !function )
                say_string( "  null\n" );
            else
            {
                say_string( "  " );
                say_string(function);
                say_char('\n');
            }
            return !(count++ < 10 && pc != 0 && 1+(uint64_t)pc != 0);
        }
        backtrace_full(state, 1, &full_callback, &error_callback, NULL);
  #endif
#endif
    }
    say_eol();

    recursing.report = false;

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



extern void* __libc_malloc(size_t size);
void *malloc(size_t size)
{
    HEADER(malloc);

    // the libc machinery I use during init time needs a malloc, so I use the
    // internal one to avoid a loop
    if(initializing)
        return (void*)__libc_malloc(size);

    return report((int64_t)size, -1, (int64_t)orig(size), __func__);
}

extern void* __libc_calloc(size_t nmemb, size_t size);
void *calloc(size_t nmemb, size_t size)
{
    HEADER(calloc);

    // the libc machinery I use during init time needs a malloc, so I use the
    // internal one to avoid a loop
    if(initializing)
        return (void*)__libc_calloc(nmemb, size);

    return report((int64_t)nmemb, (int64_t)size, (int64_t)orig(nmemb, size), __func__);
}

void *realloc(void *ptr, size_t size)
{
    HEADER(realloc);
    return report((int64_t)ptr, (int64_t)size, (int64_t)orig(ptr, size), __func__);
}

int   posix_memalign(void **memptr, size_t alignment, size_t size)
{
    HEADER(posix_memalign);
    int result = orig(memptr, alignment, size);
    if( result != 0 )
        die("posix_memalign failed!");

    report((int64_t)alignment, (int64_t)size, (int64_t)*memptr, __func__);
    return result;
}

void *aligned_alloc(size_t alignment, size_t size)
{
    HEADER(aligned_alloc);
    return report((int64_t)alignment, (int64_t)size, (int64_t)orig(alignment, size), __func__);
}

void *valloc(size_t size)
{
    die("%s UNTRACED\n", __func__);
}

void *memalign(size_t alignment, size_t size)
{
    die("%s UNTRACED\n", __func__);
}

void *pvalloc(size_t size)
{
    die("%s UNTRACED\n", __func__);
}

void free(void *ptr)
{
    HEADER(free);
    orig(ptr);

    report((int64_t)ptr, -1, -1, __func__);
}
