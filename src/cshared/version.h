#pragma once

#include <cstdio>
#include <cstring>

#ifndef DAB_VERSION
#error "DAB_VERSION must be supplied by the build"
#endif

inline bool dab_print_version_if_requested(int argc, char **argv, const char *tool)
{
    for (int i = 1; i < argc; i++)
    {
        if (strcmp(argv[i], "--version") == 0)
        {
            printf("Dab %s %s\n", tool, DAB_VERSION);
            return true;
        }
    }
    return false;
}
