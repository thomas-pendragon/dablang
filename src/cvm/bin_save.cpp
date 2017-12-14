#include "cvm.h"

static void _twrite(std::vector<byte> &out, const byte *data, size_t size)
{
    for (size_t i = 0; i < size; i++)
    {
        out.push_back(data[i]);
    }
}

template <typename T>
static void _twrite(std::vector<byte> &out, T value)
{
    _twrite(out, (const byte *)&value, sizeof(value));
}

template <typename T>
static void _twrite(std::vector<byte> &out, std::vector<T> value)
{
    for (const auto &item : value)
    {
        _twrite(out, item);
    }
}

void DabVM::dump_vm(FILE *out)
{
    BinHeader               dump_header;
    std::vector<BinSection> dump_sections = sections;
    std::vector<byte>       dump_data;

    dump_sections.erase(
        std::remove_if(dump_sections.begin(), dump_sections.end(),
                       [](BinSection section) { return std::string("func") == section.name; }));

    BinSection func_section;
    memcpy(func_section.name, "func", 4);
    std::vector<BinFunction> dump_functions;
    for (auto it : functions)
    {
        if (!it.second.regular)
            continue;

        BinFunction bin_func;
        bin_func.symbol  = it.first;
        bin_func.klass   = -1;
        bin_func.address = it.second.address;
        dump_functions.push_back(bin_func);
    }
    func_section.zero1  = 0;
    func_section.zero2  = 0;
    func_section.zero3  = 1;
    func_section.length = dump_functions.size() * sizeof(BinFunction);

    dump_sections.push_back(func_section);

    memcpy(dump_header.dab, "DAB\0", 4);
    dump_header.version        = 2;
    dump_header.section_count  = dump_sections.size();
    dump_header.size_of_header = sizeof(BinHeader) + dump_header.section_count * sizeof(BinSection);

    auto new_pos = dump_header.size_of_header;

    for (auto &section : dump_sections)
    {
        auto pos    = section.pos;
        auto length = section.length;

        section.pos = new_pos;

        if (section.zero3 == 0)
        {
            auto ptr = instructions.raw_base_data() + pos;

            _twrite(dump_data, (byte *)ptr, length);
        }
        else
        {
            _twrite(dump_data, dump_functions);
        }

        section.zero3 = 0;

        new_pos += length;
    }

    dump_header.size_of_data = dump_data.size();

    fwrite(&dump_header, sizeof(BinHeader), 1, out);
    for (auto &section : dump_sections)
    {
        fwrite(&section, sizeof(BinSection), 1, out);
    }
    fwrite(&dump_data[0], 1, dump_data.size(), out);
}
