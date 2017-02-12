#pragma once

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <assert.h>
#include <string>
#include <vector>
#include <map>
#include <functional>
#include <algorithm>
#include <cctype>

typedef unsigned char byte;

template <typename T>
T min(T a, T b)
{
    return (a < b) ? a : b;
}

struct Buffer
{
    byte * data   = nullptr;
    size_t length = 0;

    Buffer();
    Buffer(const Buffer &other);
    ~Buffer();
    Buffer &operator=(const Buffer &other);
    void resize(size_t new_length);
    void append(const byte *data, size_t data_length);
};

struct Stream
{
    uint8_t  read_uint8();
    uint16_t read_uint16();
    uint64_t read_uint64();

    std::string read_vlc_string();

    Buffer read_vlc_buffer();

    void append(const byte *data, size_t length);

    void append(Stream &stream, size_t length);

    void seek(size_t position);

    size_t length() const;
    size_t position() const;
    bool   eof() const;

  private:
    Buffer buffer;
    size_t _position = 0;

    byte * data() const;
    size_t remaining() const;

    template <typename T>
    T _read()
    {
        assert(remaining() >= sizeof(T));
        auto ret = *(T *)data();
        _position += sizeof(T);
        return ret;
    }
};

struct DabFunction
{
    bool                  regular = true;
    std::function<void()> extra   = nullptr;

    size_t      address = -1;
    std::string name;
    int         n_locals = 0;
};

enum
{
    VAL_INVALID = 0,
    VAL_FRAME_PREV_IP,
    VAL_FRAME_PREV_STACK,
    VAL_FRAME_COUNT_ARGS,
    VAL_FRAME_COUNT_VARS,
    VAL_RETVAL,
    VAL_CONSTANT,
    VAL_VARIABLE,
    VAL_STACK,
};

enum
{
    TYPE_INVALID = 0,
    TYPE_FIXNUM,
    TYPE_STRING,
    TYPE_BOOLEAN,
    TYPE_NIL,
    TYPE_SYMBOL,
};

struct DabValue
{
    int kind = VAL_INVALID;
    int type = TYPE_INVALID;

    int64_t     fixnum;
    std::string string;
    bool        boolean;

    void dump() const;

    std::string class_name() const;

    void print(FILE *out, bool debug = false) const;

    bool truthy() const;
};
