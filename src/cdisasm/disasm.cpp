#include "../cshared/shared.h"
#include "../cshared/bytecode_string_validation.h"
#include "../cshared/disasm.h"
#include "../cshared/stream.h"
#include "../cshared/version.h"

#ifdef _WIN32
#include <io.h>
#include <fcntl.h>
#define SET_BINARY_MODE(handle) _setmode(handle, O_BINARY)
#else
#define SET_BINARY_MODE(handle) ((void)0)
#endif

FILE *output = stdout;

struct DisasmContext
{
    std::vector<std::string>   section_labels;
    std::map<int, std::string> labels;
};

struct StreamReader : public BaseReader
{
    Stream &stream;
    StreamReader(Stream &stream, uint64_t &position) : BaseReader(position), stream(stream)
    {
    }

    virtual uint64_t raw_read(void *buffer, uint64_t size) override
    {
        auto raw_data   = stream.raw_base_data();
        auto length     = stream.raw_base_length();
        auto offset     = position();
        auto max_length = std::min(size, length - offset);

        memcpy(buffer, raw_data + offset, (size_t)max_length);

        return max_length;
    }

    bool feof()
    {
        return stream.eof();
    }
};

static const char *LINEINFO_FORMAT        = "/* %8" PRIu64 ": */ ";
static const char *LEGACY_LINEINFO_FORMAT = "%8" PRIu64 ": ";

void parse_substream(Stream &stream, uint64_t start, bool no_numbers, bool legacy_numbers = false)
{
    uint64_t                      position = 0;
    StreamReader                  reader(stream, position);
    DisasmProcessor<StreamReader> processor(reader, "cdisasm", "decode", start);

    fprintf(stderr, "cdisasm: parse substream %d bytes\n", (int)stream.length());
    processor.go(
        [start, no_numbers, legacy_numbers](uint64_t pos, std::string info)
        {
            if (no_numbers)
            {
                fprintf(output, "    ");
            }
            else
            {
                fprintf(output, legacy_numbers ? LEGACY_LINEINFO_FORMAT : LINEINFO_FORMAT,
                        start + pos);
            }
            fprintf(output, "%s\n", info.c_str());
        });
}

void parse_data_substream(Stream &input_stream, uint64_t start, bool no_numbers)
{
    uint64_t     position = 0;
    StreamReader reader(input_stream, position);

    AsmStream<StreamReader> stream(reader);

    std::string string;
    bool        use_string = false;
    uint64_t    string_pos = 0;

    // fprintf(stderr, "data stream (%d)\n", (int)start);

    while (true)
    {
        try
        {
            auto          pos   = stream.position();
            unsigned char byte  = stream.read_uint8();
            bool          ascii = byte >= 32 && byte <= 127;

            // fprintf(stderr, "data stream (%d): %d (%c)\n", (int)pos, (int)byte, (char)byte);

            if (ascii)
            {
                if (!use_string)
                {
                    string_pos = pos;
                }
                use_string = true;
                string += byte;
            }
            else if (use_string)
            {
                use_string = false;
                if (byte == 0)
                {
                    if (!no_numbers)
                    {
                        fprintf(output, LINEINFO_FORMAT, start + string_pos);
                    }
                    else
                    {
                        fprintf(output, "    ");
                    }
                    fprintf(output, "W_STRING \"%s\"\n", string.c_str());
                }
                else
                {
                    size_t i = 0;
                    for (auto ch : string)
                    {
                        if (!no_numbers)
                        {
                            fprintf(output, LINEINFO_FORMAT, start + string_pos + i);
                        }
                        else
                        {
                            fprintf(output, "    ");
                        }
                        fprintf(output, "W_BYTE %d\n", (int)ch);
                        i++;
                    }

                    if (!no_numbers)
                    {
                        fprintf(output, LINEINFO_FORMAT, start + string_pos);
                    }
                    else
                    {
                        fprintf(output, "    ");
                    }
                    fprintf(output, "W_BYTE %d\n", (int)byte);
                }
                string = "";
            }
            else
            {
                if (!no_numbers)
                {
                    fprintf(output, LINEINFO_FORMAT, start + pos);
                }
                else
                {
                    fprintf(output, "    ");
                }
                fprintf(output, "W_BYTE %d\n", (int)byte);
            }
        }
        catch (EOFError)
        {
            if (use_string)
            {
                size_t i = 0;
                for (auto ch : string)
                {
                    if (!no_numbers)
                    {
                        fprintf(output, LINEINFO_FORMAT, start + string_pos + i);
                    }
                    else
                    {
                        fprintf(output, "    ");
                    }
                    fprintf(output, "W_BYTE %d\n", (int)ch);
                    i++;
                }
            }
            break;
        }
    }
}

void parse_symbol_substream(Stream &input_stream, uint64_t start, bool no_numbers)
{
    uint64_t     position = 0;
    StreamReader reader(input_stream, position);

    AsmStream<StreamReader> stream(reader);

    while (true)
    {
        try
        {
            auto pos    = stream.position();
            auto symbol = stream.read_uint64();
            if (!no_numbers)
            {
                fprintf(output, LINEINFO_FORMAT, start + pos);
            }
            else
            {
                fprintf(output, "    ");
            }
            fprintf(output, "W_SYMBOL %" PRIu64 "\n", symbol);
        }
        catch (EOFError)
        {
            break;
        }
    }
}

void parse_class_substream(Stream &input_stream, uint64_t start, bool no_numbers)
{
    uint64_t     position = 0;
    StreamReader reader(input_stream, position);

    AsmStream<StreamReader> stream(reader);

    while (true)
    {
        try
        {
            auto pos = stream.position();
            // class index arg1 = parent class index arg2 = name
            auto index  = stream.read_uint16();
            auto parent = stream.read_uint16();
            auto name   = stream.read_uint16();
            auto temp_n = stream.read_uint16();
            assert(temp_n == 0);
            if (!no_numbers)
            {
                fprintf(output, LINEINFO_FORMAT, start + pos);
            }
            else
            {
                fprintf(output, "    ");
            }
            fprintf(output, "W_CLASS %" PRIu16 ", %" PRIu16 ", %" PRIu16 "\n", index, parent, name);
        }
        catch (EOFError)
        {
            break;
        }
    }
}

void parse_func_ex_substream(Stream &input_stream, uint64_t start, bool no_numbers)
{
    uint64_t     position = 0;
    StreamReader reader(input_stream, position);

    AsmStream<StreamReader> stream(reader);

    while (true)
    {
        try
        {
            auto pos         = stream.position();
            auto symbol      = stream.read_uint16();
            auto class_index = stream.read_int16();
            auto address     = stream.read_uint64();
            auto arg_count   = stream.read_uint16();
            auto length      = stream.read_uint64();
            auto flags       = stream.read_uint8();

            const char *extrasep = "    ";

            if (!no_numbers)
            {
                fprintf(output, LINEINFO_FORMAT, start + pos);
                extrasep = "                ";
            }
            else
            {
                fprintf(output, "    ");
            }
            fprintf(output,
                    "W_METHOD %" PRIu16 ", %" PRId16 ", %" PRIu64 ", %" PRId16 ", %" PRIu64
                    ", %" PRIu8 "\n",
                    symbol, class_index, address, arg_count, length, flags);

            for (int i = 0; i < arg_count + 1; i++)
            {
                auto symbol_index = stream.read_int16();
                auto class_index  = stream.read_int16();

                fprintf(output, "%s", extrasep);
                fprintf(output, "W_METHOD_ARG %" PRId16 ", %" PRId16 "\n", symbol_index,
                        class_index);
            }
        }
        catch (EOFError)
        {
            break;
        }
    }
}

// TODO: move to Stream
void read_stream(Stream &stream, FILE *input = stdin, bool close_input = false)
{
#ifdef DAB_PLATFORM_WINDOWS
    if (input == stdin)
    {
        freopen(NULL, "rb", input);
        SET_BINARY_MODE(_fileno(input));
    }
#endif
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

bool parse_bool_arg(int argc, char **argv, const std::string &arg)
{
    for (int i = 1; i < argc; i++)
    {
        if (arg == argv[i])
            return true;
    }
    return false;
}

void parse_headers(DisasmContext &context, BinHeader *base_header)
{
    auto *header   = &base_header->header;
    auto *sections = base_header->sections;

    fprintf(output, "/* disasm */\n");
    fprintf(output, "    W_HEADER %d\n", (int)header->version);
    fprintf(output, "    W_OFFSET %" PRIu64 "\n", (uint64_t)header->offset);
    for (size_t i = 0; i < header->section_count; i++)
    {
        auto section = sections[i];

        std::string label_name = std::string("_") + section.name;
        std::transform(label_name.begin(), label_name.end(), label_name.begin(), ::toupperc);

        auto base_label_name = label_name;
        int  label_counter   = 2;

        while (true)
        {
            if (!std::count(context.section_labels.begin(), context.section_labels.end(),
                            label_name))
            {
                break;
            }
            char number[12];
            snprintf(number, sizeof(number), "%d", label_counter++);
            label_name = base_label_name + number;
        }

        context.section_labels.push_back(label_name);

        fprintf(output, "    W_SECTION %s, \"%s\"\n", label_name.c_str(), section.name);
    }
    fprintf(output, "    W_END_HEADER\n\n");
}

int unsafe_main(int argc, char **argv)
{
    if (dab_print_version_if_requested(argc, argv, "disassembler"))
    {
        return 0;
    }

    DisasmContext context;

    bool raw          = parse_bool_arg(argc, argv, "--raw");
    bool with_headers = parse_bool_arg(argc, argv, "--with-headers");
    bool no_numbers   = parse_bool_arg(argc, argv, "--no-numbers");

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

    if (raw)
    {
        parse_substream(stream, 0, no_numbers, true);
    }
    else
    {
        BinHeader         *base_header = nullptr;
        BinDabHeader      *header      = nullptr;
        BinSection        *sections    = nullptr;
        ValidatedBinHeader validated_header;
        const bool         version_3 = is_version_3_bytecode(stream);
        if (version_3)
        {
            std::string validation_error;
            if (!stream.read_validated_header(validated_header, validation_error))
            {
                fprintf(stderr, "cdisasm: invalid bytecode header: %s.\n",
                        validation_error.c_str());
                return 1;
            }
            if (!validate_bytecode_string_data(stream, validated_header,
                                               DabStringDataConsumer::DISASSEMBLER,
                                               validation_error))
            {
                fprintf(stderr, "cdisasm: invalid bytecode String/symbol data: %s.\n",
                        validation_error.c_str());
                return 1;
            }
            header      = &validated_header.header;
            base_header = stream.peek_header();
        }
        else
        {
            base_header = stream.peek_header();
            header      = &base_header->header;
            sections    = base_header->sections;
        }

        fprintf(stderr, "cdisasm: %d sections\n", (int)header->section_count);
        if (with_headers)
        {
            parse_headers(context, base_header);
        }

        for (size_t i = 0; i < header->section_count; i++)
        {
            auto section = version_3 ? validated_header.sections[i] : sections[i];
            fprintf(stderr, "cdisasm: section[%d] '%s' [address %" PRIu64 " length %" PRIu64 "]\n",
                    (int)i, section.name, section.pos, section.length);

            if (with_headers)
            {
                fprintf(output, "%s:\n", context.section_labels[i].c_str());
            }

            std::string section_name = section.name;
            auto        start_pos    = section.pos;

            if (section_name == "code")
            {
                auto substream = stream.section_stream(i);
                parse_substream(substream, start_pos, no_numbers);
            }
            else if (with_headers &&
                     (section_name == "data" || section_name == "symd" || section_name == "ndat"))
            {
                auto substream = stream.section_stream(i);
                parse_data_substream(substream, start_pos, no_numbers);
            }
            else if (with_headers && section_name == "symb")
            {
                auto substream = stream.section_stream(i);
                parse_symbol_substream(substream, start_pos, no_numbers);
            }
            else if (with_headers && section_name == "clas")
            {
                auto substream = stream.section_stream(i);
                parse_class_substream(substream, start_pos, no_numbers);
            }
            else if (with_headers && section_name == "fext")
            {
                auto substream = stream.section_stream(i);
                parse_func_ex_substream(substream, start_pos, no_numbers);
            }

            if (with_headers)
            {
                fprintf(output, "\n");
            }
        }
    }

    return 0;
}

int main(int argc, char **argv)
{
    try
    {
        return unsafe_main(argc, argv);
    }
    catch (const DabUnknownOpcodeError &error)
    {
        return dab_report_unknown_opcode(error);
    }
}
