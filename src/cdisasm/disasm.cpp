#include <stdio.h>
#include <vector>
#include <assert.h>

#include "../cshared/opcodes.h"
#include "../cshared/opcodes_format.h"
#include "../cshared/opcodes_debug.h"
#include "../cshared/asm_stream.h"

#define countof(x) (sizeof(x) / sizeof(x[0]))

int main(int argc, char **argv)
{
    bool raw = (argc == 2) && (std::string(argv[1]) == "--raw");

    if (!raw)
    {
        // skip header
        const auto    header_size = 3 + 4 * 8;
        unsigned char header[header_size];
        fread(header, 1, header_size, stdin);
    }

    size_t position = 0;
    while (!feof(stdin))
    {
        auto      pos = position;
        AsmStream stream(position);
        if (!stream.read())
        {
            break;
        }
        unsigned char opcode = stream[0];
        assert(opcode < countof(g_opcodes));
        const auto &data = g_opcodes[opcode];
        std::string info;
        for (const auto &arg : data.args)
        {
            switch (arg)
            {
            case ARG_UINT8:
                stream.read_uint8(info);
                break;
            case ARG_UINT16:
                stream.read_uint16(info);
                break;
            case ARG_UINT64:
                stream.read_uint64(info);
                break;
            case ARG_VLC:
                stream.read_vlc(info);
                break;
            }
        }
        info = data.name + " " + info;
        printf("%8lX: %s\n", pos, info.c_str());
    }

    return 0;
}
