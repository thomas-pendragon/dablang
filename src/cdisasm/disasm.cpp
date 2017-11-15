#include "../cshared/shared.h"
#include "../cshared/disasm.h"
#include "../cshared/stream.h"

FILE *output = stdout;

struct DisasmContext
{
    std::vector<std::string> section_labels;
    std::map<int, std::string> labels;
};

struct StreamReader : public BaseReader
{
    Stream &stream;
    StreamReader(Stream &stream, size_t &position) : BaseReader(position), stream(stream)
    {
    }

    virtual size_t raw_read(void *buffer, size_t size) override
    {
        auto data       = stream.raw_base_data();
        auto length     = stream.raw_base_length();
        auto offset     = position();
        auto max_length = std::min(size, length - offset);

        memcpy(buffer, data + offset, max_length);

        return max_length;
    }

    bool feof()
    {
        return stream.eof();
    }
};

void parse_substream(Stream &stream, size_t start, bool no_numbers)
{
    size_t                        position = 0;
    StreamReader                  reader(stream, position);
    DisasmProcessor<StreamReader> processor(reader);

    fprintf(stderr, "cdisasm: parse substream %d bytes\n", (int)stream.length());
    processor.go([start, no_numbers](size_t pos, std::string info) {
        if (no_numbers)
        {
            fprintf(output, "    ");
        }
        else
        {
            fprintf(output, "%8ld: ", start + pos);
        }
        fprintf(output, "%s\n", info.c_str());
    });
}

// TODO: move to Stream
void read_stream(Stream &stream)
{
    byte buffer[1024];
    while (!feof(stdin))
    {
        size_t bytes = fread(buffer, 1, 1024, stdin);
        if (bytes)
        {
            stream.append(buffer, bytes);
        }
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

void parse_headers(DisasmContext &context, BinHeader *header)
{
    fprintf(output, "/* disasm */\n");
    fprintf(output, "    W_HEADER 2\n");
    for (size_t i = 0; i < header->section_count; i++)
    {
        auto section = header->sections[i];

        std::string label_name = std::string("_") + section.name;
        std::transform(label_name.begin(), label_name.end(), label_name.begin(), ::toupper);

        auto base_label_name = label_name;
        int  label_counter   = 2;

        while (true)
        {
            if (!std::count(context.section_labels.begin(), context.section_labels.end(),
                            label_name))
            {
                break;
            }
            char number[8];
            sprintf(number, "%d", label_counter++);
            label_name = base_label_name + number;
        }

        context.section_labels.push_back(label_name);

        fprintf(output, "    W_SECTION %s, \"%s\"\n", label_name.c_str(), section.name);
    }
    fprintf(output, "    W_END_HEADER\n\n");
}

int main(int argc, char **argv)
{
    DisasmContext context;

    bool raw          = parse_bool_arg(argc, argv, "--raw");
    bool with_headers = parse_bool_arg(argc, argv, "--with-headers");
    bool no_numbers   = parse_bool_arg(argc, argv, "--no-numbers");

    Stream stream;
    read_stream(stream);

    if (raw)
    {
        parse_substream(stream, 0, no_numbers);
    }
    else
    {
        auto header = stream.peek_header();
        fprintf(stderr, "cdisasm: %d sections\n", (int)header->section_count);
        if (with_headers)
        {
            parse_headers(context, header);
        }

        for (size_t i = 0; i < header->section_count; i++)
        {
            auto section = header->sections[i];
            fprintf(stderr, "cdisasm: section[%d] '%s'\n", (int)i, section.name);
            if (with_headers)
            {
                fprintf(output, "%s:\n", context.section_labels[i].c_str());
            }
            std::string section_name = section.name;
            if (section_name == "code")
            {
                auto substream = stream.section_stream(i);
                parse_substream(substream, section.pos, no_numbers);
            }
            if (with_headers)
            {
                fprintf(output, "\n");
            }
        }
    }

    return 0;
}
