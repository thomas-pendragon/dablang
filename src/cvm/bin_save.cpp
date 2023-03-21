#include "cvm.h"

static void _twrite(std::vector<byte> &out, const byte *data, size_t size)
{
    for (size_t i = 0; i < size; i++)
    {
        out.push_back(data[i]);
    }
}

static void _ttwrite(std::vector<byte> &out, const byte *data, size_t size)
{
    for (size_t i = 0; i < size; i++)
    {
        fprintf(stderr, "%02x ", data[i]);
        if (i % 16 == 15)
        {
            fprintf(stderr, "\n");
        }
        out.push_back(data[i]);
    }
    fprintf(stderr, "\n");
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

enum
{
    TEMP_REGULAR         = 0,
    TEMP_FUNC_SECTION    = 1,
    TEMP_SYMBOLS_SECTION = 2,
    TEMP_SYMDATA_SECTION = 3,
};

void DabVM::dump_vm(FILE *out)
{
    BinDabHeader            dump_header;
    std::vector<BinSection> dump_sections = sections;
    std::vector<byte>       dump_data;

    dump_sections.erase(std::remove_if(dump_sections.begin(), dump_sections.end(),
                                       [](BinSection section)
                                       {
                                           std::string name = section.name;
                                           return name == "func" || name == "symb" ||
                                                  name == "symd" || name == "fext";
                                       }),
                        dump_sections.end());

    auto last_code_index = -1;
    auto last_data_index = -1;

    for (int i = 0; i < (int)dump_sections.size(); i++)
    {
        auto       &section = dump_sections[i];
        std::string name    = section.name;

        if (name == "code")
            last_code_index = std::max(last_code_index, i);

        if (name == "data")
            last_data_index = std::max(last_data_index, i);
    }

    fprintf(stderr, "vm/binsave: last code = %d last data = %d\n", last_code_index,
            last_data_index);

    for (int i = 0, section_index = 0; i < (int)dump_sections.size(); i++, section_index++)
    {
        auto       &section = dump_sections[i];
        std::string name    = section.name;

        bool previous_code = name == "code" && section_index != last_code_index;
        bool previous_data = name == "data" && section_index != last_data_index;
        bool remove        = previous_code || previous_data;

        if (remove)
        {
            fprintf(stderr, "vm/binsave: remove previous section %d '%s'\n", section_index,
                    name.c_str());
            dump_sections.erase(dump_sections.begin() + i);
            i--;
        }
    }

    (void)last_code_index;
    (void)last_data_index;

    auto &code_section = sections[last_code_index];

    BinSection func_section = {};
    memcpy(func_section.name, "func", 4);
    std::vector<BinFunctionEx> dump_functions;
    for (auto it : functions)
    {
        const auto &fun = it.second;

        if (!fun.regular)
            continue;

        if (fun.source_ring < this->last_ring_offset)
        {
            if (options.verbose)
            {
                fprintf(stderr,
                        "vm/binsave: will skip function '%s' (ring source: %" PRIu64
                        ", last ring offset: %" PRIu64 ")\n",
                        get_symbol(it.first).c_str(), fun.source_ring, this->last_ring_offset);
            }
            continue;
        }

        if (options.verbose)
        {
            fprintf(stderr, "vm/binsave: will save function '%s' (ring source: %" PRId64 ")\n",
                    get_symbol(it.first).c_str(), fun.source_ring);
        }

        BinFunction bin_func;
        bin_func.symbol  = it.first;
        bin_func.klass   = DAB_CLASS_NIL;
        bin_func.address = it.second.address;
        if (fun.new_method)
        {
            bin_func.address += code_section.pos + code_section.length;
        }
        dump_functions.push_back(bin_func);
    }
    func_section.special_index = TEMP_FUNC_SECTION;
    func_section.length        = dump_functions.size() * sizeof(BinFunction);

    BinSection symb_section;
    memcpy(symb_section.name, "symb", 4);

    BinSection symd_section;
    memcpy(symd_section.name, "symd", 4);

    std::vector<byte>     symd_data;
    std::vector<uint64_t> symb_data;
    for (auto sym : symbols)
    {
        auto pos = symd_data.size();

        if (sym.source_ring < this->last_ring_offset)
        {
            if (options.verbose)
            {
                fprintf(stderr,
                        "vm/binsave: will skip symbol '%s' (ring source: %" PRIu64
                        ", last ring offset: %" PRIu64 ")\n",
                        sym.value.c_str(), sym.source_ring, this->last_ring_offset);
            }
            continue;
        }

        if (options.verbose)
        {
            fprintf(stderr,
                    "vm/binsave: write symbol '%s' (ring source: %" PRIu64
                    ", last ring offset: %" PRIu64 ")\n",
                    sym.value.c_str(), sym.source_ring, this->last_ring_offset);
        }

        symb_data.push_back(pos);
        for (char ch : sym.value)
        {
            symd_data.push_back(ch);
        }
        symd_data.push_back(0);
    }
    symb_section.special_index = TEMP_SYMBOLS_SECTION;
    symb_section.length        = symb_data.size() * sizeof(uint64_t);

    symd_section.special_index = TEMP_SYMDATA_SECTION;
    symd_section.length        = symd_data.size();

    dump_sections.push_back(symd_section);
    auto symd_section_index = dump_sections.size() - 1;
    dump_sections.push_back(symb_section);
    dump_sections.push_back(func_section);

    memcpy(dump_header.dab, "DAB\0", 4);
    dump_header.version        = 3;
    dump_header.offset         = last_ring_offset;
    dump_header.section_count  = dump_sections.size();
    dump_header.size_of_header = sizeof(BinHeader) + dump_header.section_count * sizeof(BinSection);

    auto new_pos = dump_header.size_of_header;

    auto code_offset = new_pos - instructions.peek_header()->header.size_of_header;
    for (auto &func : dump_functions)
    {
        func.address += code_offset;
    }

    for (auto &section : dump_sections)
    {
        auto pos    = section.pos;
        auto length = section.length;

        section.pos = new_pos + this->last_ring_offset;

        if (section.special_index == TEMP_REGULAR)
        {
            auto ptr = instructions.raw_base_data() + pos;

            _twrite(dump_data, (byte *)ptr, (size_t)length);

            if (std::string(section.name) == "code")
            {
                fprintf(stderr, "vm/binsave: inject %d bytes of new code\n",
                        (int)new_instructions.length);
                _ttwrite(dump_data, new_instructions.data, new_instructions.length);
                length += new_instructions.length;
                section.length += new_instructions.length;
            }
        }
        else if (section.special_index == TEMP_FUNC_SECTION)
        {
            _twrite(dump_data, dump_functions);
        }
        else if (section.special_index == TEMP_SYMDATA_SECTION)
        {
            _twrite(dump_data, symd_data);
        }
        else if (section.special_index == TEMP_SYMBOLS_SECTION)
        {
            auto offset = dump_sections[symd_section_index].pos;
            for (auto &symb : symb_data)
            {
                symb += offset;
            }
            _twrite(dump_data, symb_data);
        }

        section.special_index = 0;

        new_pos += length;
    }

    dump_header.size_of_data = dump_data.size();

    fwrite(&dump_header, sizeof(BinHeader), 1, out);
    for (auto &section : dump_sections)
    {
        if (options.verbose)
        {
            fprintf(stderr,
                    "vm/binsave: write section '%s' pos = %" PRIu64 " length = %" PRIu64 "\n",
                    section.name, section.pos, section.length);
        }
        fwrite(&section, sizeof(BinSection), 1, out);
    }
    fwrite(&dump_data[0], 1, dump_data.size(), out);
}
