#include "bytecode_string_validation.h"

#include "opcode_validation.h"

#include <cstring>
#include <limits>

namespace
{
const uint64_t STRING_REFERENCE_SIZE = sizeof(uint64_t);

bool section_name_is(const BinSection &section, const char name[5])
{
    return memcmp(section.name, name, sizeof(section.name)) == 0;
}

bool section_range(const Stream &input, const BinDabHeader &header, const BinSection &section,
                   const char *section_name, uint64_t &start, uint64_t &length, std::string &error)
{
    if (section.pos < header.offset)
    {
        error = std::string(section_name) + " section starts before the artifact";
        return false;
    }
    if (section.length > std::numeric_limits<uint64_t>::max() - section.pos)
    {
        error = std::string(section_name) + " section address range overflows uint64";
        return false;
    }

    const uint64_t input_length = input.raw_base_length();
    start                       = section.pos - header.offset;
    length                      = section.length;
    if (start > input_length || length > input_length - start)
    {
        error = std::string(section_name) + " section range is outside the artifact";
        return false;
    }
    if (start > std::numeric_limits<size_t>::max() || length > std::numeric_limits<size_t>::max())
    {
        error = std::string(section_name) + " section range exceeds platform limits";
        return false;
    }

    return true;
}

bool validate_string_table(const Stream &input, const BinDabHeader &header,
                           const BinSection &section, const char *table_name,
                           DabStringDataConsumer consumer, const Stream *vm_address_space,
                           std::string &error)
{
    if (section.length % STRING_REFERENCE_SIZE != 0)
    {
        error = std::string(table_name) + " section length is not a multiple of 8";
        return false;
    }

    uint64_t table_start;
    uint64_t table_length;
    if (!section_range(input, header, section, table_name, table_start, table_length, error))
    {
        return false;
    }

    const byte    *data        = input.raw_base_data();
    const uint64_t entry_count = table_length / STRING_REFERENCE_SIZE;
    for (uint64_t index = 0; index < entry_count; index++)
    {
        const uint64_t entry_offset = table_start + index * STRING_REFERENCE_SIZE;
        uint64_t       reference;
        memcpy(&reference, data + (size_t)entry_offset, sizeof(reference));

        const std::string entry = std::string(table_name) + " entry " + std::to_string(index);
        const byte       *string_data;
        uint64_t          string_offset;
        uint64_t          string_space_length;
        if (consumer == DabStringDataConsumer::VM)
        {
            string_data         = vm_address_space->raw_base_data();
            string_offset       = reference;
            string_space_length = vm_address_space->raw_base_length();
        }
        else if (consumer == DabStringDataConsumer::COVERAGE_DUMPER)
        {
            if (reference < header.offset)
            {
                error = entry + " reference is outside the artifact";
                return false;
            }
            string_data         = input.raw_base_data();
            string_offset       = reference - header.offset;
            string_space_length = input.raw_base_length();
        }
        else
        {
            if (reference < header.offset)
            {
                // A standalone disassembly may retain references into an earlier Ring.
                continue;
            }
            string_offset       = reference - header.offset;
            string_space_length = input.raw_base_length();
            if (string_offset >= string_space_length)
            {
                // The disassembler renders the native address without dereferencing it.
                continue;
            }
            string_data = input.raw_base_data();
        }

        if (string_offset >= string_space_length)
        {
            error = entry + " reference is outside the artifact";
            return false;
        }

        const uint64_t remaining = string_space_length - string_offset;
        if (string_offset > std::numeric_limits<size_t>::max() ||
            remaining > std::numeric_limits<size_t>::max())
        {
            error = entry + " String range exceeds platform limits";
            return false;
        }
        if (!memchr(string_data + (size_t)string_offset, 0, (size_t)remaining))
        {
            error = entry + " String is not NUL-terminated within the artifact";
            return false;
        }
    }

    return true;
}

uint64_t fixed_argument_size(OpcodeArg argument)
{
    switch (argument)
    {
    case OpcodeArg::ARG_UINT8:
    case OpcodeArg::ARG_INT8:
        return 1;
    case OpcodeArg::ARG_UINT16:
    case OpcodeArg::ARG_INT16:
    case OpcodeArg::ARG_REG:
    case OpcodeArg::ARG_SYMBOL:
        return 2;
    case OpcodeArg::ARG_UINT32:
    case OpcodeArg::ARG_INT32:
    case OpcodeArg::ARG_FLOAT:
    case OpcodeArg::ARG_STRING4:
        return 4;
    case OpcodeArg::ARG_UINT64:
    case OpcodeArg::ARG_INT64:
        return 8;
    case OpcodeArg::ARG_VLC:
    case OpcodeArg::ARG_REGLIST:
    case OpcodeArg::ARG_CSTRING:
        return 0;
    }
    return 0;
}

bool consume_bytes(uint64_t amount, uint64_t end, uint64_t &position)
{
    if (position > end || amount > end - position)
    {
        return false;
    }
    position += amount;
    return true;
}

bool validate_instruction_arguments(const byte *data, uint64_t instruction_address, uint64_t end,
                                    const DabOpcodeInfo &opcode, uint64_t &position,
                                    std::string &error)
{
    for (const auto argument : opcode.args)
    {
        const uint64_t fixed_size = fixed_argument_size(argument);
        if (fixed_size)
        {
            if (!consume_bytes(fixed_size, end, position))
            {
                error = "code instruction at byte " + std::to_string(instruction_address) +
                        " is truncated";
                return false;
            }
            continue;
        }

        if (argument == OpcodeArg::ARG_REGLIST)
        {
            if (!consume_bytes(1, end, position))
            {
                error = "code instruction at byte " + std::to_string(instruction_address) +
                        " is truncated";
                return false;
            }
            const uint64_t register_bytes = (uint64_t)data[position - 1] * sizeof(uint16_t);
            if (!consume_bytes(register_bytes, end, position))
            {
                error = "code instruction at byte " + std::to_string(instruction_address) +
                        " has a truncated register list";
                return false;
            }
        }
        else if (argument == OpcodeArg::ARG_VLC)
        {
            if (!consume_bytes(1, end, position))
            {
                error = "code instruction at byte " + std::to_string(instruction_address) +
                        " is truncated";
                return false;
            }
            uint64_t length = data[position - 1];
            if (length == 255)
            {
                if (!consume_bytes(sizeof(uint64_t), end, position))
                {
                    error = "code instruction at byte " + std::to_string(instruction_address) +
                            " has a truncated variable-length String size";
                    return false;
                }
                memcpy(&length, data + (size_t)(position - sizeof(uint64_t)), sizeof(length));
            }
            if (!consume_bytes(length, end, position))
            {
                error = "code instruction at byte " + std::to_string(instruction_address) +
                        " has a truncated variable-length String";
                return false;
            }
        }
        else
        {
            if (position > end)
            {
                error = "code instruction at byte " + std::to_string(instruction_address) +
                        " is truncated";
                return false;
            }
            const uint64_t remaining  = end - position;
            const void    *terminator = memchr(data + (size_t)position, 0, (size_t)remaining);
            if (!terminator)
            {
                error = "code instruction at byte " + std::to_string(instruction_address) +
                        " has an unterminated C String";
                return false;
            }
            const byte *terminator_byte = static_cast<const byte *>(terminator);
            position                    = (uint64_t)(terminator_byte - data) + 1;
        }
    }

    return true;
}

bool validate_load_string(const byte *data, const Stream &address_space, uint64_t instruction_start,
                          uint64_t instruction_address, std::string &error)
{
    uint64_t reference;
    uint64_t length;
    memcpy(&reference, data + (size_t)(instruction_start + 1 + sizeof(uint16_t)),
           sizeof(reference));
    memcpy(&length, data + (size_t)(instruction_start + 1 + sizeof(uint16_t) + sizeof(uint64_t)),
           sizeof(length));

    const std::string entry        = "LOAD_STRING at byte " + std::to_string(instruction_address);
    const uint64_t    input_length = address_space.raw_base_length();
    if (reference > input_length || length > input_length - reference)
    {
        error = entry + " range is outside the artifact";
        return false;
    }
    if (reference > std::numeric_limits<size_t>::max() ||
        length > std::numeric_limits<size_t>::max())
    {
        error = entry + " range exceeds platform limits";
        return false;
    }

    return true;
}

bool validate_code_section(const Stream &input, const BinDabHeader &header,
                           const BinSection &section, DabStringDataConsumer consumer,
                           const Stream *vm_address_space, std::string &error)
{
    uint64_t start;
    uint64_t length;
    if (!section_range(input, header, section, "code", start, length, error))
    {
        return false;
    }

    const byte    *data     = input.raw_base_data();
    const uint64_t end      = start + length;
    uint64_t       position = start;
    while (position < end)
    {
        const uint64_t instruction_start   = position;
        const uint64_t instruction_address = section.pos + instruction_start - start;
        const uint8_t  opcode_value        = data[position++];

        // Original #17 owns the diagnostic and exit status for unknown opcodes. Leave that
        // byte to the existing consumer path without reading any metadata for it here.
        if (opcode_value >= countof(g_opcodes))
        {
            return true;
        }

        const auto &opcode = g_opcodes[opcode_value];
        if (!validate_instruction_arguments(data, instruction_address, end, opcode, position,
                                            error))
        {
            return false;
        }
        if (consumer == DabStringDataConsumer::VM && opcode_value == OP_LOAD_STRING &&
            !validate_load_string(data, *vm_address_space, instruction_start, instruction_address,
                                  error))
        {
            return false;
        }
    }

    return true;
}
} // namespace

bool is_version_3_bytecode(const Stream &input)
{
    if (input.raw_base_length() < 8)
    {
        return false;
    }

    const byte *data = input.raw_base_data();
    uint32_t    version;
    memcpy(&version, data + 4, sizeof(version));
    return memcmp(data, "DAB\0", 4) == 0 && version == 3;
}

bool validate_bytecode_string_data(const Stream &input, const ValidatedBinHeader &header,
                                   DabStringDataConsumer consumer, std::string &error,
                                   const Stream *vm_address_space)
{
    if (consumer == DabStringDataConsumer::VM && !vm_address_space)
    {
        error = "VM String validation has no loaded address space";
        return false;
    }

    const BinSection *last_symbols = nullptr;
    for (const auto &section : header.sections)
    {
        if (consumer == DabStringDataConsumer::DISASSEMBLER &&
            (section_name_is(section, "data") || section_name_is(section, "symd") ||
             section_name_is(section, "ndat")))
        {
            uint64_t    start;
            uint64_t    length;
            const char *section_name = section_name_is(section, "symd")   ? "symd"
                                       : section_name_is(section, "ndat") ? "ndat"
                                                                          : "data";
            if (!section_range(input, header.header, section, section_name, start, length, error))
            {
                return false;
            }
        }

        if (section_name_is(section, "code") &&
            !validate_code_section(input, header.header, section, consumer, vm_address_space,
                                   error))
        {
            return false;
        }

        if (section_name_is(section, "symb"))
        {
            if (consumer == DabStringDataConsumer::DISASSEMBLER &&
                !validate_string_table(input, header.header, section, "symb", consumer,
                                       vm_address_space, error))
            {
                return false;
            }
            if (consumer == DabStringDataConsumer::VM)
            {
                // load_newformat consumes only the last symbol table in an artifact.
                last_symbols = &section;
            }
        }
        else if (section_name_is(section, "cove") &&
                 consumer != DabStringDataConsumer::DISASSEMBLER &&
                 !validate_string_table(input, header.header, section, "cove", consumer,
                                        vm_address_space, error))
        {
            return false;
        }
    }

    if (last_symbols && !validate_string_table(input, header.header, *last_symbols, "symb",
                                               consumer, vm_address_space, error))
    {
        return false;
    }

    error.clear();
    return true;
}
