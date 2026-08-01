#include "stream.h"

#include <algorithm>
#include <limits>
#include <new>
#include <stdexcept>
#include <utility>

Stream Stream::section_stream(uint64_t section_index)
{
    const uint64_t fixed_header_size = sizeof(BinDabHeader);
    const uint64_t section_size      = sizeof(BinSection);
    const uint64_t maximum_uint64    = std::numeric_limits<uint64_t>::max();

    if (buffer.length < fixed_header_size)
    {
        throw std::invalid_argument("section stream header is truncated");
    }

    BinDabHeader header = {};
    memcpy(&header, buffer.data, sizeof(header));

    BinSection section = {};
    if (header.version == 3)
    {
        if (!_section_header_cache_set)
        {
            ValidatedBinHeader parsed_header;
            std::string        validation_error;
            _section_header_cache_valid = read_validated_header(parsed_header, validation_error);
            if (_section_header_cache_valid)
            {
                _section_header_cache = std::move(parsed_header);
                _section_header_cache_error.clear();
            }
            else
            {
                _section_header_cache_error = std::move(validation_error);
            }
            _section_header_cache_set = true;
        }
        if (!_section_header_cache_valid)
        {
            throw std::invalid_argument("invalid bytecode header: " + _section_header_cache_error);
        }
        if (section_index >= _section_header_cache.sections.size())
        {
            throw std::out_of_range("section index exceeds validated section table");
        }
        header  = _section_header_cache.header;
        section = _section_header_cache.sections[(size_t)section_index];
    }
    else
    {
        if (header.section_count > (maximum_uint64 - fixed_header_size) / section_size)
        {
            throw std::invalid_argument("section stream table size overflows uint64");
        }
        const uint64_t table_end = fixed_header_size + header.section_count * section_size;
        if (table_end > buffer.length)
        {
            throw std::invalid_argument("section stream table exceeds input");
        }
        if (section_index >= header.section_count)
        {
            throw std::out_of_range("section index exceeds section table");
        }
        memcpy(&section, buffer.data + fixed_header_size + section_index * section_size,
               sizeof(section));
        if (section.pos < header.offset)
        {
            throw std::invalid_argument("section position precedes header offset");
        }
        const uint64_t local_start = section.pos - header.offset;
        if (local_start > buffer.length || section.length > buffer.length - local_start)
        {
            throw std::invalid_argument("section range exceeds input");
        }
    }

    Stream ret;
    auto   start  = section.pos - header.offset;
    auto   length = section.length;
    ret.buffer    = Buffer(this->buffer, start, length);
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
    const uint64_t maximum_uint64    = std::numeric_limits<uint64_t>::max();

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
    if (header.size_of_data > maximum_uint64 - header.size_of_header)
    {
        error = "declared bytecode size overflows uint64";
        return false;
    }

    const uint64_t declared_bytecode_size = header.size_of_header + header.size_of_data;
    if (declared_bytecode_size != buffer.length)
    {
        error = "size_of_header and size_of_data do not match input size";
        return false;
    }
    if (header.offset > maximum_uint64 - header.size_of_header)
    {
        error = "section payload start overflows uint64";
        return false;
    }

    const uint64_t payload_start = header.offset + header.size_of_header;
    if (header.size_of_data > maximum_uint64 - payload_start)
    {
        error = "section payload end overflows uint64";
        return false;
    }
    const uint64_t payload_end = payload_start + header.size_of_data;

    try
    {
        struct SectionRange
        {
            uint64_t start;
            uint64_t end;
            uint64_t index;
        };

        ValidatedBinHeader parsed;
        parsed.header = header;
        if (header.section_count > parsed.sections.max_size())
        {
            error = "section count exceeds container limits";
            return false;
        }
        parsed.sections.reserve((size_t)header.section_count);
        std::vector<SectionRange> nonempty_ranges;
        nonempty_ranges.reserve((size_t)header.section_count);

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
            if (section.pos < header.offset)
            {
                error = "section " + std::to_string(index) + " position precedes header offset";
                return false;
            }
            if (section.pos < payload_start)
            {
                error = "section " + std::to_string(index) + " starts before declared payload";
                return false;
            }
            if (section.pos > payload_end)
            {
                error = "section " + std::to_string(index) + " starts after declared payload";
                return false;
            }
            if (section.length > maximum_uint64 - section.pos)
            {
                error = "section " + std::to_string(index) + " range overflows uint64";
                return false;
            }
            if (section.length > payload_end - section.pos)
            {
                error = "section " + std::to_string(index) + " range exceeds declared payload";
                return false;
            }
            if (section.length != 0)
            {
                nonempty_ranges.push_back({section.pos, section.pos + section.length, index});
            }
            parsed.sections.push_back(section);
        }

        std::sort(nonempty_ranges.begin(), nonempty_ranges.end(),
                  [](const SectionRange &left, const SectionRange &right)
                  {
                      if (left.start != right.start)
                          return left.start < right.start;
                      if (left.end != right.end)
                          return left.end < right.end;
                      return left.index < right.index;
                  });
        for (size_t index = 1; index < nonempty_ranges.size(); index++)
        {
            const auto &previous = nonempty_ranges[index - 1];
            const auto &current  = nonempty_ranges[index];
            if (current.start < previous.end)
            {
                error = "section " + std::to_string(previous.index) + " overlaps section " +
                        std::to_string(current.index);
                return false;
            }
        }

        validated = std::move(parsed);
    }
    catch (const std::length_error &)
    {
        error = "section table exceeds container limits";
        return false;
    }
    catch (const std::bad_alloc &)
    {
        error = "section table allocation failed";
        return false;
    }

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
    _section_header_cache_set   = false;
    _section_header_cache_valid = false;
    _section_header_cache       = {};
    _section_header_cache_error.clear();
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
