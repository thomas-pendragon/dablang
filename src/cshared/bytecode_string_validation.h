#pragma once

#include "stream.h"

#include <string>

enum class DabStringDataConsumer
{
    VM,
    DISASSEMBLER,
    COVERAGE_DUMPER,
};

// Version 3 stores symbol and coverage names as native-byte-order uint64_t pointers to
// NUL-terminated bytes. LOAD_STRING instead carries an explicit pointer and length.
// This preflight validates only those existing encodings and complete code records.
bool validate_bytecode_string_data(const Stream &input, const ValidatedBinHeader &header,
                                   DabStringDataConsumer consumer, std::string &error,
                                   const Stream *vm_address_space = nullptr);

// Safely distinguishes the version 3 container before callers inspect its header.
bool is_version_3_bytecode(const Stream &input);
