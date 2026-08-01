#pragma once

#include "../cshared/stream.h"

#include <string>

// Validates the version 3 pointer tables consumed as NUL-terminated Strings by the VM.
// References remain native-byte-order uint64_t values and may point into the middle of data.
bool validate_bytecode_string_tables(const Stream &input, const ValidatedBinHeader &header,
                                     std::string &error);
