#include "cvm.h"

static void _twrite(std::vector<byte> &out, byte *data, size_t size)
{
    for (size_t i = 0; i < size; i++)
    {
        out.push_back(data[i]);
    }
}

template <typename T>
static void _twrite(std::vector<byte> &out, T value)
{
    _twrite(out, &value, sizeof(value));
}

void DabVM::dump_vm(FILE *out)
{

    BinHeader               dump_header;
    std::vector<BinSection> dump_sections = sections;
    std::vector<byte>       dump_data;

    strcpy(dump_header.dab, "DAB");
    dump_header.version        = 2;
    dump_header.size_of_header = sizeof(BinHeader) + dump_sections.size() * sizeof(BinSection);
    dump_header.section_count  = dump_sections.size();

    auto new_pos = dump_header.size_of_header;

    for (auto &section : sections)
    {
        auto pos    = section.pos;
        auto length = section.length;

        section.pos = new_pos;

        auto ptr = instructions.raw_base_data() + pos;

        _twrite(dump_data, (byte *)ptr, length);

        new_pos += length;
    }

    dump_header.size_of_data = dump_data.size();

    fwrite(&dump_header, sizeof(BinHeader), 1, out);
    for (auto &section : sections)
    {
        fwrite(&section, sizeof(BinSection), 1, out);
    }
    fwrite(&dump_data[0], 1, dump_data.size(), out);
}
