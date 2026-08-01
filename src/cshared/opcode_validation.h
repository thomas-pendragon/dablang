#pragma once

#include "../cshared/shared.h"
#include "../cshared/opcodes.h"
#include "../cshared/opcodes_format.h"
#include "../cshared/opcodes_debug.h"

static const int DAB_UNKNOWN_OPCODE_EXIT_STATUS = 2;

struct DabUnknownOpcodeError : public std::exception
{
    const char *consumer;
    const char *stage;
    uint8_t     opcode;
    uint64_t    position;

    DabUnknownOpcodeError(const char *consumer, const char *stage, uint8_t opcode,
                          uint64_t position)
        : consumer(consumer), stage(stage), opcode(opcode), position(position)
    {
    }

    const char *what() const noexcept override
    {
        return "unknown opcode";
    }
};

inline const DabOpcodeInfo &dab_opcode_info_or_throw(uint8_t opcode, const char *consumer,
                                                     const char *stage, uint64_t position)
{
    if (opcode >= countof(g_opcodes))
    {
        throw DabUnknownOpcodeError(consumer, stage, opcode, position);
    }

    return g_opcodes[opcode];
}

inline int dab_report_unknown_opcode(const DabUnknownOpcodeError &error)
{
    fprintf(stderr, "%s: %s: unknown opcode %u (0x%02x) at byte %" PRIu64 ".\n", error.consumer,
            error.stage, (unsigned int)error.opcode, (unsigned int)error.opcode, error.position);
    return DAB_UNKNOWN_OPCODE_EXIT_STATUS;
}
