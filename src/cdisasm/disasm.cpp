#include "../cshared/shared.h"
#include "../cshared/disasm.h"

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

    DisasmProcessor processor;

    processor.go([](size_t pos, std::string info) { printf("%8ld: %s\n", pos, info.c_str()); });

    return 0;
}
