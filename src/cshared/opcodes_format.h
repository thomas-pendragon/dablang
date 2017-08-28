#pragma once

#include <vector>
#include <string>

enum
{
    ARG_UINT8,
    ARG_UINT16,
    ARG_UINT64,
    ARG_INT16,
    ARG_VLC,
    ARG_REG,
    ARG_SYMBOL,
};

struct DabOpcodeInfo
{
    int              opcode;
    std::string      name;
    std::vector<int> args;
};
