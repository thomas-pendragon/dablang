#include <stdio.h>
#include <vector>

#include "../cshared/opcodes.h"
#include "../cshared/opcodes_format.h"
#include "../cshared/opcodes_debug.h"

struct AsmStream
{
    std::vector<unsigned char> data;
    void read(size_t size = 1)
    {
        auto old_size = data.size();
        data.resize(old_size + size);
        fread(&data[old_size], 1, size, stdin);
    }
    unsigned char operator[](size_t index) const
    {
        return data[index];
    }
};

int main()
{
    // skip header
    const auto    header_size = 3 + 4 * 8;
    unsigned char header[header_size];
    fread(header, 1, header_size, stdin);

    while (!feof(stdin))
    {
        AsmStream stream;
        stream.read();
        unsigned char opcode = stream[0];
        printf("opcode %d\n", opcode);
    }

    return 0;
}
