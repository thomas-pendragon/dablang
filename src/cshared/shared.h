#pragma once

#ifndef __STDC_FORMAT_MACROS
#define __STDC_FORMAT_MACROS
#endif

#include <algorithm>
#include <assert.h>
#include <cctype>
#include <functional>
#include <inttypes.h>
#include <map>
#include <set>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <string>
#include <vector>

#define countof(x) (sizeof(x) / sizeof(x[0]))

typedef unsigned char byte;

template <typename T>
T min(T a, T b)
{
    return (a < b) ? a : b;
}
