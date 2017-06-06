#include "../cshared/shared.h"
#include "../cshared/opcodes.h"
#include "../cshared/opcodes_format.h"
#include "../cshared/opcodes_debug.h"
#include "../cshared/asm_stream.h"

struct AsmStream : public BaseAsmStream<>
{
    AsmStream(size_t position) : BaseAsmStream(position)
    {
    }

    uint8_t read_uint8()
    {
        return _read<uint8_t>();
    }

    uint16_t read_uint16()
    {
        return _read<uint16_t>();
    }

    uint64_t read_uint64()
    {
        return _read<uint64_t>();
    }

    int16_t read_int16()
    {
        return _read<int16_t>();
    }

    std::string read_vlc()
    {
        size_t length = _read<uint8_t>();
        if (length == 256)
        {
            length = _read<uint64_t>();
        }
        auto ptr = read(length);
        return std::string((const char *)ptr, length);
    }

    unsigned char operator[](size_t index) const
    {
        return data[index];
    }
};

struct Arg
{
    uint64_t    fixnum = 0;
    std::string string;

    Arg(uint64_t fixnum) : fixnum(fixnum)
    {
    }
    Arg(std::string string) : string(string)
    {
    }
};

struct Op
{
    size_t           code;
    std::vector<Arg> data;

    uint16_t arg_uint16(size_t index)
    {
        return data[index].fixnum;
    }

    std::string arg_string(size_t index)
    {
        return data[index].string;
    }
};

void parse_asm(bool raw, std::function<void(Op)> func)
{
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
        AsmStream stream(position);
        if (!stream.read())
        {
            break;
        }
        unsigned char opcode = stream[0];
        assert(opcode < countof(g_opcodes));
        const auto &data = g_opcodes[opcode];
        Op          op;
        op.code = opcode;
        for (const auto &arg : data.args)
        {
            switch (arg)
            {
            case ARG_UINT8:
                op.data.push_back(stream.read_uint8());
                break;
            case ARG_UINT16:
                op.data.push_back(stream.read_uint16());
                break;
            case ARG_UINT64:
                op.data.push_back(stream.read_uint64());
                break;
            case ARG_INT16:
                op.data.push_back(stream.read_int16());
                break;
            case ARG_VLC:
                op.data.push_back(stream.read_vlc());
                break;
            }
        }
        func(op);
    }
};

int main(int argc, char **argv)
{
    bool raw = (argc == 2) && (std::string(argv[1]) == "--raw");

    std::map<uint64_t, std::string>        files;
    std::map<uint64_t, std::set<uint64_t>> lines;

    parse_asm(raw, [&files, &lines](Op op) {
        if (op.code == OP_COV_FILE)
        {
            files[op.arg_uint16(0)] = op.arg_string(1);
        }
        if (op.code == OP_COV)
        {
            lines[op.arg_uint16(0)].insert(op.arg_uint16(1));
        }
    });

    printf("[");
    int j = 0;
    for (auto f : files)
    {
        if (j++ > 0)
            printf(",");
        printf("{\"file\": \"%s\", \"lines\": [", f.second.c_str());
        auto &file_lines = lines[f.first];
        int   i          = 0;
        for (auto line : file_lines)
        {
            if (i++ > 0)
                printf(", ");
            printf("%d", (int)line);
        }
        printf("]}");
    }
    printf("]\n");

    return 0;
}
