#include "stream.h"

#include <limits>
#include <utility>

Stream Stream::section_stream(uint64_t section_index)
{
    Stream ret;
    auto   header  = peek_header();
    auto   section = header->sections[section_index];
    auto   start   = section.pos - header->header.offset;
    auto   length  = section.length;
    ret.buffer     = Buffer(this->buffer, start, length);
    return ret;
}

BinHeader *Stream::peek_header()
{
    return (BinHeader *)buffer.data;
}

bool Stream::read_validated_header(ValidatedBinHeader &validated, std::string &error) const
{
    const uint64_t fixed_header_size = sizeof(BinDabHeader);
    const uint64_t section_size      = sizeof(BinSection);

    if (buffer.length < fixed_header_size)
    {
        error = "fixed header is truncated (expected 40 bytes)";
        return false;
    }

    BinDabHeader header = {};
    memcpy(&header, buffer.data, sizeof(header));

    if (memcmp(header.dab, "DAB", 3) != 0)
    {
        error = "magic must be DAB";
        return false;
    }
    if (header.dab[3] != 0)
    {
        error = "header zero marker must be 0";
        return false;
    }
    if (header.version != 3)
    {
        error = "unsupported bytecode version (expected 3)";
        return false;
    }

    if (header.section_count >
        (std::numeric_limits<uint64_t>::max() - fixed_header_size) / section_size)
    {
        error = "section table size overflows uint64";
        return false;
    }
    if (header.section_count > std::numeric_limits<size_t>::max() / sizeof(BinSection))
    {
        error = "section count exceeds platform limits";
        return false;
    }

    const uint64_t expected_header_size = fixed_header_size + header.section_count * section_size;
    if (header.size_of_header != expected_header_size)
    {
        error = "size_of_header does not match section_count";
        return false;
    }
    if (expected_header_size > buffer.length)
    {
        error = "declared section table exceeds input";
        return false;
    }

    ValidatedBinHeader parsed;
    parsed.header = header;
    if (header.section_count > parsed.sections.max_size())
    {
        error = "section count exceeds container limits";
        return false;
    }
    parsed.sections.reserve((size_t)header.section_count);

    const byte *section_data = buffer.data + fixed_header_size;
    for (uint64_t index = 0; index < header.section_count; index++)
    {
        BinSection section = {};
        memcpy(&section, section_data + index * section_size, sizeof(section));
        if (section.zero1 != 0 || section.zero2 != 0 || section.special_index != 0)
        {
            error = "section " + std::to_string(index) + " reserved fields must be zero";
            return false;
        }
        parsed.sections.push_back(section);
    }

    validated = std::move(parsed);
    error.clear();
    return true;
}

const char *Stream::string_ptr(uint64_t address)
{
    return (const char *)(buffer.data + address);
}

std::string Stream::cstring_data(uint64_t address)
{
    auto ptr = buffer.data + address;
    return std::string((const char *)ptr);
}

uint64_t Stream::uint64_data(uint64_t address)
{
    auto     ptr = buffer.data + address;
    uint64_t ret;
    memcpy(&ret, ptr, sizeof(ret));
    return ret;
}

uint8_t Stream::uint8_data(uint64_t address)
{
    auto ptr = buffer.data + address;
    auto ret = *(uint8_t *)ptr;
    return ret;
}

uint16_t Stream::uint16_data(uint64_t address)
{
    auto     ptr = buffer.data + address;
    uint16_t ret;
    memcpy(&ret, ptr, sizeof(ret));
    return ret;
}

int8_t Stream::read_int8()
{
    return _read<int8_t>();
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

int64_t Stream::read_int64()
{
    return _read<int64_t>();
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

float Stream::read_float()
{
    return _read<float>();
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
    uint64_t len = read_uint8();
    if (len == 255)
    {
        len = read_uint64();
    }
    assert(len <= remaining());
    std::string ret((const char *)data(), (size_t)len);
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

void Stream::append(const byte *data, uint64_t length)
{
    buffer.append(data, length);
}

void Stream::append(Stream &stream, uint64_t length)
{
    assert(stream.remaining() >= length);
    append(stream.data(), length);
    stream._position += length;
}

void Stream::seek(uint64_t position)
{
    assert(position < length());
    _position = position;
}

uint64_t Stream::length() const
{
    return buffer.length;
}

uint64_t Stream::position() const
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

uint64_t Stream::remaining() const
{
    if (buffer.length <= _position)
        return 0;
    return buffer.length - _position;
}
