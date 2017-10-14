#pragma once

#include <vector>
#include <string>

enum class OpcodeArg
{
    ARG_UINT8,
    ARG_UINT16,
    ARG_UINT32,
    ARG_UINT64,
    ARG_INT16,
    ARG_INT32,
    ARG_VLC,
    ARG_REG,
    ARG_SYMBOL,
    ARG_REGLIST,
    ARG_STRING4,
    ARG_CSTRING,
};

struct DabOpcodeInfo
{
    int                    opcode;
    std::string            name;
    std::vector<OpcodeArg> args;
};
