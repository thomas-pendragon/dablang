#include "../cshared/shared.h"
#include "../cshared/opcodes.h"
#include "../cshared/opcodes_format.h"
#include "../cshared/opcodes_debug.h"
#include "../cshared/asm_stream.h"
#include "../cshared/stream.h"

struct Arg
{
    uint64_t    fixnum = 0;
    std::string string;
    float       floatnum = 0.0f;

    Arg(int8_t fixnum) : fixnum((uint64_t)fixnum)
    {
    }
    Arg(int16_t fixnum) : fixnum((uint64_t)fixnum)
    {
    }
    Arg(int32_t fixnum) : fixnum((uint64_t)fixnum)
    {
    }
    Arg(int64_t fixnum) : fixnum((uint64_t)fixnum)
    {
    }
    Arg(uint8_t fixnum) : fixnum((uint64_t)fixnum)
    {
    }
    Arg(uint16_t fixnum) : fixnum((uint64_t)fixnum)
    {
    }
    Arg(uint32_t fixnum) : fixnum((uint64_t)fixnum)
    {
    }
    Arg(uint64_t fixnum) : fixnum(fixnum)
    {
    }
    Arg(float floatnum) : floatnum(floatnum)
    {
    }
    Arg(dab_register_t reg) : fixnum(reg.value())
    {
    }
    Arg(std::vector<dab_register_t> regs)
    {
        (void)regs;
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
        return (uint16_t)data[index].fixnum;
    }
};

void read_stream(Stream &stream, FILE *input, bool close_input)
{
    byte buffer[1024];
    while (!feof(input))
    {
        size_t bytes = fread(buffer, 1, 1024, input);
        if (bytes)
        {
            stream.append(buffer, bytes);
        }
    }
    if (close_input)
    {
        fclose(input);
    }
}

void parse_stream(Stream &stream, std::function<void(Op)> func)
{
    while (!stream.eof())
    {
        auto opcode = stream.read_uint8();
        assert(opcode < countof(g_opcodes));
        const auto &data = g_opcodes[opcode];
        Op          op;
        op.code = opcode;
        for (const auto &arg : data.args)
        {
            switch (arg)
            {
            case OpcodeArg::ARG_INT8:
                op.data.push_back(stream.read_int8());
                break;
            case OpcodeArg::ARG_UINT8:
                op.data.push_back(stream.read_uint8());
                break;
            case OpcodeArg::ARG_UINT16:
                op.data.push_back(stream.read_uint16());
                break;
            case OpcodeArg::ARG_UINT64:
                op.data.push_back(stream.read_uint64());
                break;
            case OpcodeArg::ARG_INT16:
                op.data.push_back(stream.read_int16());
                break;
            case OpcodeArg::ARG_VLC:
                op.data.push_back(stream.read_vlc_string());
                break;
            case OpcodeArg::ARG_UINT32:
                op.data.push_back(stream.read_uint32());
                break;
            case OpcodeArg::ARG_INT32:
                op.data.push_back(stream.read_int32());
                break;
            case OpcodeArg::ARG_INT64:
                op.data.push_back(stream.read_int64());
                break;
            case OpcodeArg::ARG_REG:
                op.data.push_back(stream.read_reg());
                break;
            case OpcodeArg::ARG_SYMBOL:
                op.data.push_back(stream.read_symbol());
                break;
            case OpcodeArg::ARG_REGLIST:
                op.data.push_back(stream.read_reglist());
                break;
            case OpcodeArg::ARG_STRING4:
                op.data.push_back(stream.read_string4());
                break;
            case OpcodeArg::ARG_CSTRING:
                op.data.push_back(stream.read_cstring());
                break;
            case OpcodeArg::ARG_FLOAT:
                op.data.push_back(stream.read_float());
                break;
            }
        }
        func(op);
    }
};

int main(int argc, char **argv)
{
    std::map<uint64_t, std::string>        files;
    std::map<uint64_t, std::set<uint64_t>> lines;

    FILE *input       = stdin;
    bool  close_input = false;

    for (int argn = 1; argn < argc; argn++)
    {
        auto arg = argv[argn];
        if (strstr(arg, "--") == NULL)
        {
            input       = fopen(arg, "rb");
            close_input = true;

            if (!input)
            {
                fprintf(stderr, "disasm: error: cannot open file <%s> for reading.\n", arg);
                exit(1);
            }
        }
    }

    Stream stream;
    read_stream(stream, input, close_input);

    auto base_header = stream.peek_header();
    auto header      = &base_header->header;
    auto sections    = base_header->sections;

    fprintf(stderr, "cdumpcov: %d sections\n", (int)header->section_count);
    for (size_t i = 0; i < header->section_count; i++)
    {
        auto section = sections[i];
        fprintf(stderr, "cdumpcov: section[%d] '%s'\n", (int)i, section.name);
        std::string section_name = section.name;
        if (section_name == "cove")
        {
            auto size_of_cov_file    = sizeof(uint64_t);
            auto number_of_cov_files = section.length / size_of_cov_file;
            fprintf(stderr, "cdumpcov: %d cov files\n", (int)number_of_cov_files);
            for (size_t j = 0; j < number_of_cov_files; j++)
            {
                auto ptr    = section.pos + size_of_cov_file * j;
                auto data   = stream.uint64_data(ptr);
                auto string = stream.cstring_data(data);
                fprintf(stderr, "cdumpcov: cov[%d] %p -> %p -> '%s'\n", (int)j, (void *)ptr,
                        (void *)data, string.c_str());
                files[j + 1] = string;
            }
        }
        if (section_name == "code")
        {
            auto substream = stream.section_stream(i);
            parse_stream(substream, [&files, &lines](Op op) {
                if (op.code == OP_COV)
                {
                    lines[op.arg_uint16(0)].insert(op.arg_uint16(1));
                }
            });
        }
    }

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
