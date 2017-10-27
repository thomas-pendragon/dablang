#include "stream.h"

Stream Stream::section_stream(uint64_t section_index)
{
    Stream ret;
    auto   header  = peek_header();
    auto   section = header->sections[section_index];
    auto   start   = section.pos;
    auto   length  = section.length;
    ret.buffer     = Buffer(this->buffer, start, length);
    return ret;
}

BinHeader *Stream::peek_header()
{
    return (BinHeader *)buffer.data;
}

std::string Stream::string_data(size_t address, size_t length)
{
    auto ptr = buffer.data + address;
    return std::string((const char *)ptr, length);
}

std::string Stream::cstring_data(size_t address)
{
    auto ptr = buffer.data + address;
    return std::string((const char *)ptr);
}

uint64_t Stream::uint64_data(size_t address)
{
    auto ptr = buffer.data + address;
    auto ret = *(uint64_t *)ptr;
    return ret;
}

uint16_t Stream::uint16_data(size_t address)
{
    auto ptr = buffer.data + address;
    auto ret = *(uint16_t *)ptr;
    return ret;
}

uint8_t Stream::read_uint8()
{
    return _read<uint8_t>();
}

int16_t Stream::read_int16()
{
    return _read<int16_t>();
}

int32_t Stream::read_int32()
{
    return _read<int32_t>();
}

dab_register_t Stream::read_reg()
{
    return read_uint16();
}

uint16_t Stream::read_uint16()
{
    return _read<uint16_t>();
}

uint32_t Stream::read_uint32()
{
    return _read<uint32_t>();
}

uint64_t Stream::read_uint64()
{
    return _read<uint64_t>();
}

std::vector<dab_register_t> Stream::read_reglist()
{
    auto count = read_uint8();

    std::vector<dab_register_t> ret;
    for (size_t i = 0; i < count; i++)
    {
        ret.push_back(read_reg());
    }
    return ret;
}

std::string Stream::read_vlc_string()
{
    size_t len = read_uint8();
    if (len == 255)
    {
        len = read_uint64();
    }
    assert(len <= remaining());
    std::string ret((const char *)data(), len);
    _position += len;
    return ret;
}

std::string Stream::read_string4()
{
    std::string ret;
    for (int i = 0; i < 4; i++)
    {
        ret += _read<char>();
    }
    return ret;
}

std::string Stream::read_cstring()
{
    std::string ret;
    for (int i = 0; i < 4; i++)
    {
        auto c = _read<char>();
        ;
        if (c == 0)
            break;
        ret += c;
    }
    return ret;
}

void Stream::append(const byte *data, size_t length)
{
    buffer.append(data, length);
}

void Stream::append(Stream &stream, size_t length)
{
    assert(stream.remaining() >= length);
    append(stream.data(), length);
    stream._position += length;
}

void Stream::seek(size_t position)
{
    assert(position < length());
    _position = position;
}

size_t Stream::length() const
{
    return buffer.length;
}

size_t Stream::position() const
{
    return _position;
}

bool Stream::eof() const
{
    return remaining() == 0;
}

byte *Stream::data() const
{
    return buffer.data + _position;
}

size_t Stream::remaining() const
{
    if (buffer.length <= _position)
        return 0;
    return buffer.length - _position;
}
