#pragma once

#if !defined(__MINGW32__) && !defined(_WIN32)

#define DAB_PLATFORM_UNIX 1

#else

#define DAB_PLATFORM_WINDOWS 1

#endif
