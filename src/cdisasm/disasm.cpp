#include "../cshared/shared.h"
#include "../cshared/disasm.h"
#include "../cshared/stream.h"

FILE *output = stdout;

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

void parse_substream(Stream &stream, size_t start)
{
    size_t                        position = 0;
    StreamReader                  reader(stream, position);
    DisasmProcessor<StreamReader> processor(reader);

    fprintf(stderr, "cdisasm: parse substream %d bytes\n", (int)stream.length());
    processor.go([start](size_t pos, std::string info) {
        fprintf(output, "%8ld: %s\n", start + pos, info.c_str());
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

void parse_headers(BinHeader *header)
{
    fprintf(output, "/* disasm */\n");
    fprintf(output, "    W_HEADER 2\n");
    for (size_t i = 0; i < header->section_count; i++)
    {
        auto section = header->sections[i];
        fprintf(output, "    W_SECTION %d, \"%s\"\n", (int)section.pos, section.name);
    }
    fprintf(output, "    W_END_HEADER\n\n");
}

int main(int argc, char **argv)
{
    bool raw          = parse_bool_arg(argc, argv, "--raw");
    bool with_headers = parse_bool_arg(argc, argv, "--with-headers");

    Stream stream;
    read_stream(stream);

    if (raw)
    {
        parse_substream(stream, 0);
    }
    else
    {
        auto header = stream.peek_header();
        fprintf(stderr, "cdisasm: %d sections\n", (int)header->section_count);
        if (with_headers)
        {
            parse_headers(header);
        }

        for (size_t i = 0; i < header->section_count; i++)
        {
            auto section = header->sections[i];
            fprintf(stderr, "cdisasm: section[%d] '%s'\n", (int)i, section.name);
            std::string section_name = section.name;
            if (section_name == "code")
            {
                auto substream = stream.section_stream(i);
                parse_substream(substream, section.pos);
            }
        }
    }

    return 0;
}
