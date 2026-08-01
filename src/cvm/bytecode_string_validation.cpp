#include "bytecode_string_validation.h"

#include <cstring>
#include <limits>

namespace
{
const uint64_t STRING_REFERENCE_SIZE = sizeof(uint64_t);

bool section_name_is(const BinSection &section, const char name[5])
{
    return memcmp(section.name, name, sizeof(section.name)) == 0;
}

bool validate_string_table(const Stream &input, const BinDabHeader &header,
                           const BinSection &section, const char *table_name, std::string &error)
{
    if (section.length % STRING_REFERENCE_SIZE != 0)
    {
        error = std::string(table_name) + " section length is not a multiple of 8";
        return false;
    }

    if (section.pos < header.offset)
    {
        error = std::string(table_name) + " section starts before the artifact";
        return false;
    }

    const uint64_t input_length  = input.raw_base_length();
    const uint64_t section_start = section.pos - header.offset;
    if (section_start > input_length || section.length > input_length - section_start)
    {
        error = std::string(table_name) + " section range is outside the artifact";
        return false;
    }
    if (section_start > std::numeric_limits<size_t>::max() ||
        section.length > std::numeric_limits<size_t>::max())
    {
        error = std::string(table_name) + " section range exceeds platform limits";
        return false;
    }

    const byte    *data        = input.raw_base_data();
    const uint64_t entry_count = section.length / STRING_REFERENCE_SIZE;
    for (uint64_t index = 0; index < entry_count; index++)
    {
        const uint64_t entry_offset = section_start + index * STRING_REFERENCE_SIZE;
        uint64_t       reference;
        memcpy(&reference, data + (size_t)entry_offset, sizeof(reference));

        const std::string entry = std::string(table_name) + " entry " + std::to_string(index);
        if (reference < header.offset)
        {
            error = entry + " reference starts before the artifact";
            return false;
        }

        const uint64_t string_offset = reference - header.offset;
        if (string_offset >= input_length)
        {
            error = entry + " reference is outside the artifact";
            return false;
        }

        const uint64_t remaining = input_length - string_offset;
        if (string_offset > std::numeric_limits<size_t>::max() ||
            remaining > std::numeric_limits<size_t>::max())
        {
            error = entry + " String range exceeds platform limits";
            return false;
        }
        if (!memchr(data + (size_t)string_offset, 0, (size_t)remaining))
        {
            error = entry + " String is not NUL-terminated within the artifact";
            return false;
        }
    }

    return true;
}
} // namespace

bool validate_bytecode_string_tables(const Stream &input, const ValidatedBinHeader &header,
                                     std::string &error)
{
    const BinSection *symbols = nullptr;
    for (const auto &section : header.sections)
    {
        if (section_name_is(section, "symb"))
        {
            // load_newformat consumes only the last symbol table in an artifact.
            symbols = &section;
        }
        else if (section_name_is(section, "cove") &&
                 !validate_string_table(input, header.header, section, "cove", error))
        {
            return false;
        }
    }

    if (symbols && !validate_string_table(input, header.header, *symbols, "symb", error))
    {
        return false;
    }

    error.clear();
    return true;
}
