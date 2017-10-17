#pragma once

#include "../cshared/shared.h"

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

struct dab_register_t
{
    uint16_t _value;

    uint16_t value() const
    {
        return _value;
    }
    bool nil() const
    {
        return _value == 0xFFFF;
    }

    dab_register_t(uint16_t _value) : _value(_value)
    {
    }

    static dab_register_t nilreg()
    {
        return dab_register_t(0xFFFF);
    }
};

struct Stream
{
    uint8_t  read_uint8();
    int16_t  read_int16();
    int32_t  read_int32();
    uint16_t read_uint16();
    uint32_t read_uint32();
    uint64_t read_uint64();

    dab_register_t read_reg();

    uint16_t read_symbol()
    {
        return read_uint16();
    }

    std::vector<dab_register_t> read_reglist();

    std::string read_vlc_string();

    std::string read_string4();
    std::string read_cstring();

    Buffer read_vlc_buffer();

    void append(const byte *data, size_t length);

    void append(Stream &stream)
    {
        append(stream, stream.remaining());
    }
    void append(Stream &stream, size_t length);

    void seek(size_t position);

    size_t length() const;
    size_t position() const;
    bool   eof() const;

    void rewind()
    {
        seek(0);
    }

    size_t remaining() const;

    const byte *raw_base_data() const
    {
        return buffer.data;
    }
    size_t raw_base_length() const
    {
        return buffer.length;
    }

    std::string cstring_data(size_t address);
    std::string string_data(size_t address, size_t length);
    uint16_t uint16_data(size_t address);
    uint64_t uint64_data(size_t address);

  private:
    Buffer buffer;
    size_t _position = 0;

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
