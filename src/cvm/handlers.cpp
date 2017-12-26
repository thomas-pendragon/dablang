#include "../cshared/dab.h"

#ifndef DAB_PLATFORM_WINDOWS

#include <stdio.h>
#include <execinfo.h>
#include <signal.h>
#include <stdlib.h>
#include <unistd.h>

void handler(int sig)
{
    void *array[10];

    int size = backtrace(array, 10);

    fprintf(stderr, "Error: signal %d:\n", sig);
    backtrace_symbols_fd(array, size, STDERR_FILENO);
    exit(1);
}

void setup_handlers()
{
    signal(SIGSEGV, handler);
}

#else

void setup_handlers()
{
}

#endif
