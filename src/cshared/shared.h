#pragma once

#include "../cshared/dab.h"

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
#include <stdexcept>

#define countof(x) (sizeof(x) / sizeof(x[0]))

typedef unsigned char byte;

template <typename T>
T min(T a, T b)
{
    return (a < b) ? a : b;
}

typedef uint16_t dab_symbol_t;
typedef uint16_t dab_class_t;

static const dab_symbol_t DAB_SYMBOL_NIL = 0xFFFF;
static const dab_class_t  DAB_CLASS_NIL  = 0xFFFF;

inline char toupperc(char c)
{
    return (char)::toupper(c);
}
