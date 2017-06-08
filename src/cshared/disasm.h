#pragma once

#include "../cshared/shared.h"
#include "../cshared/opcodes.h"
#include "../cshared/opcodes_format.h"
#include "../cshared/opcodes_debug.h"
#include "../cshared/asm_stream.h"

template <typename TReader = StdinReader>
struct AsmStream
{
    TReader reader;

    AsmStream(size_t &position) : reader(position)
    {
    }

    void read_uint8(std::string &info)
    {
        auto value = _read<uint8_t>();
        char output[32];
        sprintf(output, "%d", value);
        if (info.length())
            info += ", ";
        info += output;
    }

    void read_int16(std::string &info)
    {
        auto value = _read<int16_t>();
        char output[32];
        sprintf(output, "%d", value);
        if (info.length())
            info += ", ";
        info += output;
    }

    void read_uint16(std::string &info)
    {
        auto value = _read<uint16_t>();
        char output[32];
        sprintf(output, "%d", value);
        if (info.length())
            info += ", ";
        info += output;
    }

    void read_uint64(std::string &info)
    {
        auto value = _read<uint64_t>();
        char output[32];
        sprintf(output, "%" PRIu64, value);
        if (info.length())
            info += ", ";
        info += output;
    }

    void read_vlc(std::string &info)
    {
        size_t length = _read<uint8_t>();
        if (length == 256)
        {
            length = _read<uint64_t>();
        }
        auto        ptr = read(length);
        std::string output((const char *)ptr, length);
        if (info.length())
            info += ", ";
        info += output;
    }

    unsigned char operator[](size_t index) const
    {
        return reader[index];
    }

    void *read(size_t size = 1)
    {
        return reader.read(size);
    }

    template <typename T>
    T _read()
    {
        return *(T *)read(sizeof(T));
    }
};

struct DisasmProcessor
{
    void go(std::function<void(size_t, std::string)> yield)
    {
        size_t position = 0;
        while (!feof(stdin))
        {
            auto        pos = position;
            AsmStream<> stream(position);
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
                case ARG_INT16:
                    stream.read_int16(info);
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
            yield(pos, info);
        }
    }
};
