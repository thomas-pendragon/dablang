#pragma once

#include "../cshared/shared.h"

struct Buffer
{
    byte    *data   = nullptr;
    uint64_t length = 0;

    bool _dont_delete = false;

    void dump(FILE *out);

    Buffer();
    Buffer(const Buffer &other);
    Buffer(const Buffer &other, uint64_t start, uint64_t length); // nocopy
    ~Buffer();
    Buffer &operator=(const Buffer &other);
    void    resize(uint64_t new_length);
    void    append(const byte *new_data, uint64_t new_data_length);
};

struct dab_register_t
{
    uint16_t _value;

    uint16_t value() const
    {
        return _value;
    }
    bool nil() const
    {
        return _value == _nil_value;
    }

    dab_register_t() : _value(_nil_value)
    {
    }

    dab_register_t(uint16_t _value) : _value(_value)
    {
    }

    static dab_register_t nilreg()
    {
        return dab_register_t(_nil_value);
    }

    static const uint16_t _nil_value = 0xFFFF;
};

#pragma pack(push, 1)
struct BinFunctionArg
{
    dab_symbol_t symbol;
    dab_class_t  klass;
};
#pragma pack(pop)

#pragma pack(push, 1)
struct BinFunctionExBase
{
    dab_symbol_t symbol;
    dab_class_t  klass;
    uint64_t     address;
    uint16_t     arglist_count;
    uint64_t     length;
};
#pragma pack(pop)

struct BinFunctionEx : BinFunctionExBase
{
    std::vector<BinFunctionArg> args;
};

#pragma pack(push, 1)
struct BinClass
{
    dab_class_t  index;
    dab_class_t  parent;
    dab_symbol_t name;
};
#pragma pack(pop)

#pragma pack(push, 1)
struct BinSection
{
    char     name[4];
    uint32_t zero1         = 0;
    uint32_t zero2         = 0;
    uint32_t special_index = 0;
    uint64_t pos           = 0;
    uint64_t length        = 0;
};
#pragma pack(pop)

#pragma pack(push, 1)
struct BinDabHeader
{
    char     dab[4];
    uint32_t version;
    uint64_t offset;
    uint64_t size_of_header;
    uint64_t size_of_data;
    uint64_t section_count;
};
#pragma pack(pop)

#pragma pack(push, 1)
struct BinHeader
{
    BinDabHeader header;
    BinSection   sections[0];
};
#pragma pack(pop)

struct Stream
{
    BinHeader *peek_header();

    Stream section_stream(uint64_t section_index);

    int8_t   read_int8();
    int16_t  read_int16();
    int32_t  read_int32();
    int64_t  read_int64();
    uint8_t  read_uint8();
    uint16_t read_uint16();
    uint32_t read_uint32();
    uint64_t read_uint64();

    float read_float();

    dab_register_t read_reg();

    uint16_t read_symbol()
    {
        return read_uint16();
    }

    std::vector<dab_register_t> read_reglist();

    std::string read_vlc_string();

    std::string read_string4();
    std::string read_cstring();

    void append(const byte *data, uint64_t length);

    void append(Stream &stream)
    {
        append(stream, stream.remaining());
    }
    void append(Stream &stream, uint64_t length);

    void write_uint8(uint8_t data)
    {
        append((const byte *)&data, sizeof(data));
    }
    void write_uint16(uint16_t data)
    {
        append((const byte *)&data, sizeof(data));
    }
    void write_uint64(uint64_t data)
    {
        append((const byte *)&data, sizeof(data));
    }
    void write_int64(int64_t data)
    {
        append((const byte *)&data, sizeof(data));
    }

    void seek(uint64_t position);

    uint64_t length() const;
    uint64_t position() const;
    bool     eof() const;

    void rewind()
    {
        seek(0);
    }

    uint64_t remaining() const;

    const byte *raw_base_data() const
    {
        return buffer.data;
    }
    uint64_t raw_base_length() const
    {
        return buffer.length;
    }

    const char *string_ptr(uint64_t address);

    std::string cstring_data(uint64_t address);
    uint16_t    uint16_data(uint64_t address);
    uint64_t    uint64_data(uint64_t address);

    void dump(FILE *out)
    {
        buffer.dump(out);
    }

  private:
    Buffer   buffer;
    uint64_t _position = 0;

    byte *data() const;

    template <typename T>
    T _read()
    {
        assert(remaining() >= sizeof(T));
        auto ret = *(T *)data();
        _position += sizeof(T);
        return ret;
    }
};
