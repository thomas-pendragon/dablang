#pragma once

#if defined(_MSC_VER)
// C4200: nonstandard extension used : zero - sized array in struct / union
#pragma warning(disable : 4200)
#endif

#if !defined(__MINGW32__) && !defined(_WIN32)

#define DAB_PLATFORM_UNIX 1

#else

#define DAB_PLATFORM_WINDOWS 1

#endif

#define _CRT_SECURE_NO_DEPRECATE
