#pragma once

#include "../cshared/shared.h"
#include "../cshared/opcodes.h"
#include "../cshared/opcodes_format.h"
#include "../cshared/opcodes_debug.h"
#include "../cshared/asm_stream.h"

struct EOFError
{
};

template <typename TReader = StdinReader>
struct AsmStream
{
    TReader reader;

    AsmStream(TReader reader) : reader(reader)
    {
    }

    size_t position() const
    {
        return reader.position();
    }

    bool feof()
    {
        return reader.feof();
    }

    uint8_t read_uint8()
    {
        return _read<uint8_t>();
    }

    uint16_t read_uint16()
    {
        return _read<uint16_t>();
    }

    int16_t read_int16()
    {
        return _read<int16_t>();
    }

    uint64_t read_uint64()
    {
        return _read<uint64_t>();
    }

    void read_int8(std::string &info)
    {
        auto value = _read<int8_t>();
        char output[32];
        sprintf(output, "%d", value);
        if (info.length())
            info += ", ";
        info += output;
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

    void read_int32(std::string &info)
    {
        auto value = _read<int32_t>();
        char output[32];
        sprintf(output, "%d", value);
        if (info.length())
            info += ", ";
        info += output;
    }

    void read_uint32(std::string &info)
    {
        auto value = _read<uint32_t>();
        char output[32];
        sprintf(output, "%" PRIu32, value);
        if (info.length())
            info += ", ";
        info += output;
    }

    void read_reg(std::string &info)
    {
        auto value = _read<uint16_t>();
        char output[32];
        if (value == 0xFFFF)
        {
            sprintf(output, "RNIL");
        }
        else
        {
            sprintf(output, "R%d", (int)value);
        }
        if (info.length())
            info += ", ";
        info += output;
    }

    void read_reglist(std::string &info)
    {
        int count = _read<int8_t>();
        for (int i = 0; i < count; i++)
        {
            read_reg(info);
        }
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

    void read_symbol(std::string &info)
    {
        auto value = _read<uint16_t>();
        char output[32];
        sprintf(output, "S%d", value);
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

    void read_int64(std::string &info)
    {
        auto value = _read<int64_t>();
        char output[32];
        sprintf(output, "%" PRId64, value);
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

    void read_string4(std::string &info)
    {
        std::string output;
        for (int i = 0; i < 4; i++)
            output += _read<char>();

        if (info.length())
            info += ", ";
        info += output;
    }

    void read_cstring(std::string &info)
    {
        std::string output;
        while (true)
        {
            auto c = _read<char>();
            if (c == 0)
                break;
            output += c;
        }

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
        auto ptr = (T *)read(sizeof(T));
        if (!ptr)
            throw EOFError();
        return *ptr;
    }
};

template <typename TReader = StdinReader>
struct DisasmProcessor
{
    TReader reader;
    DisasmProcessor(TReader reader) : reader(reader)
    {
    }

    void go(std::function<void(size_t, std::string)> yield)
    {
        AsmStream<TReader> stream(reader);
        while (!stream.feof())
        {
            try
            {
                auto          pos    = reader.position();
                unsigned char opcode = stream.read_uint8();
                assert(opcode < countof(g_opcodes));
                const auto &data = g_opcodes[opcode];
                std::string info;
                for (const auto &arg : data.args)
                {
                    switch (arg)
                    {
                    case OpcodeArg::ARG_INT8:
                        stream.read_int8(info);
                        break;
                    case OpcodeArg::ARG_UINT8:
                        stream.read_uint8(info);
                        break;
                    case OpcodeArg::ARG_INT16:
                        stream.read_int16(info);
                        break;
                    case OpcodeArg::ARG_UINT16:
                        stream.read_uint16(info);
                        break;
                    case OpcodeArg::ARG_UINT32:
                        stream.read_uint32(info);
                        break;
                    case OpcodeArg::ARG_INT32:
                        stream.read_int32(info);
                        break;
                    case OpcodeArg::ARG_UINT64:
                        stream.read_uint64(info);
                        break;
                    case OpcodeArg::ARG_INT64:
                        stream.read_int64(info);
                        break;
                    case OpcodeArg::ARG_REG:
                        stream.read_reg(info);
                        break;
                    case OpcodeArg::ARG_VLC:
                        stream.read_vlc(info);
                        break;
                    case OpcodeArg::ARG_SYMBOL:
                        stream.read_symbol(info);
                        break;
                    case OpcodeArg::ARG_REGLIST:
                        stream.read_reglist(info);
                        break;
                    case OpcodeArg::ARG_STRING4:
                        stream.read_string4(info);
                        break;
                    case OpcodeArg::ARG_CSTRING:
                        stream.read_cstring(info);
                        break;
                    }
                }
                info = data.name + " " + info;
                yield(pos, info);
            }
            catch (EOFError)
            {
                break;
            }
        }
    }
};
