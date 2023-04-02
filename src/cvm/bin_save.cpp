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

static void _twrite(std::vector<byte> &out, BinFunctionEx value)
{
    // fprintf(stderr, "Print function... (%d args)\n", (int)value.args.size());
    // fprintf(stderr, "symbol = %d (%s)\n", (int)value.symbol,
    // $VM->get_symbol(value.symbol).c_str()); fprintf(stderr, "klass  = %d\n", (int)value.klass);
    // fprintf(stderr, "addres = %d\n", (int)value.address);
    // fprintf(stderr, "arglis = %d\n", (int)value.arglist_count);
    // fprintf(stderr, "length = %d\n", (int)value.length);

    _ttwrite(out, (const byte *)&value, sizeof(BinFunctionExBase));
    for (auto &arg : value.args)
    {
        _ttwrite(out, (const byte *)&arg, sizeof(BinFunctionArg));
    }
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
    TEMP_CLASS_SECTION   = 4,
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
                                           return name == "symb" || name == "symd" ||
                                                  name == "fext" || name == "clas";
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

    BinSection class_section = {};
    memcpy(class_section.name, "clas", 4);
    auto                  classes_to_copy = classes;
    std::vector<BinClass> dump_classes;
    for (auto it : classes_to_copy)
    {
        BinClass bin;
        bin.index  = it.first;
        bin.parent = it.second.superclass_index;
        fprintf(stderr, "vm/binsave: dump class %d: '%s'\n", (int)it.first, it.second.name.c_str());
        bin.name = get_symbol_index(it.second.name);
        dump_classes.push_back(bin);
    }
    int class_def_size          = sizeof(BinClass);
    class_section.special_index = TEMP_FUNC_SECTION;
    class_section.length        = class_def_size * classes_to_copy.size();

    BinSection func_section = {};
    memcpy(func_section.name, "fext", 4);
    std::vector<BinFunctionEx> dump_functions;
    size_t                     funssize = 0;
    auto fun_parser = [&](std::map<dab_symbol_t, DabFunction> functions, dab_class_t class_index)
    {
        for (auto it : functions)
        {
            const auto &fun = it.second;

            fprintf(stderr, "vm/binsave: consider function '%s'\n", get_symbol(it.first).c_str());

            if (!fun.dlimport && !fun.regular)
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

            const auto &fundata    = it.second;
            const auto &reflection = fundata.reflection;

            BinFunctionEx bin_func;
            bin_func.symbol        = it.first;
            bin_func.klass         = class_index;
            bin_func.address       = fundata.address;
            bin_func.length        = fundata.length;
            bin_func.arglist_count = reflection.arg_klasses.size();
            if (fun.new_method)
            {
                bin_func.address += code_section.pos + code_section.length;
            }
            for (size_t i = 0; i < bin_func.arglist_count; i++)
            {
                BinFunctionArg arg;
                arg.symbol = get_symbol_index(reflection.arg_names[i]);
                arg.klass  = reflection.arg_klasses[i];
                bin_func.args.push_back(arg);
            }
            BinFunctionArg ret;
            ret.symbol = -1;
            ret.klass  = reflection.ret_klass;
            bin_func.args.push_back(ret);
            dump_functions.push_back(bin_func);
            funssize += sizeof(BinFunctionExBase) + bin_func.args.size() * sizeof(BinFunctionArg);
        }
    };
    fun_parser(functions, DAB_CLASS_NIL);
    for (auto klass : classes)
    {
        fun_parser(klass.second.functions, klass.first);
    }

    func_section.special_index = TEMP_FUNC_SECTION;
    func_section.length        = funssize;

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

    dump_sections.push_back(class_section);
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
        else if (section.special_index == TEMP_CLASS_SECTION)
        {
            _twrite(dump_data, dump_classes);
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
