#include "cvm.h"

void DabVM::load_newformat(Stream &input)
{
    auto peeked_header = input.peek_header();

    auto mark1 = input.read_uint8();
    auto mark2 = input.read_uint8();
    auto mark3 = input.read_uint8();
    if (mark1 != 'D' || mark2 != 'A' || mark3 != 'B')
    {
        fprintf(stderr, "VM error: invalid mark (%c%c%c, expected DAB).\n", (char)mark1,
                (char)mark2, (char)mark3);
        exit(1);
    }

    auto zero_byte = input.read_uint8();
    assert(zero_byte == 0);

    auto version = input.read_uint32();
    assert(version == 3);

    auto offset = input.read_uint64();

    auto size_of_header     = input.read_uint64();
    auto size_of_data       = input.read_uint64();
    auto number_of_sections = input.read_uint64();

    fprintf(stderr, "vm: newformat: h: %d, d: %d, s: %d\n", (int)size_of_header, (int)size_of_data,
            (int)number_of_sections);
    fprintf(stderr, "vm: offset is %d\n", (int)offset);

    uint64_t code_address = 0;
    uint64_t symb_address = 0;
    uint64_t symb_length  = 0;
    bool     has_symbols  = false;

    uint64_t func_address  = 0;
    uint64_t func_length   = 0;
    bool     has_functions = false;

    uint64_t classes_address = 0;
    uint64_t classes_length  = 0;
    bool     has_classes     = false;

    for (uint32_t index = 0; index < number_of_sections; index++)
    {
        this->sections.push_back(peeked_header->sections[index]);

        auto name = input.read_string4();
        auto zero = input.read_uint32();
        assert(zero == 0);
        zero = input.read_uint32();
        assert(zero == 0);
        zero = input.read_uint32();
        assert(zero == 0);
        auto address = input.read_uint64();
        auto length  = input.read_uint64();

        fprintf(stderr, "vm: newformat: section %d: name '%s' address %p/%d length %d\n", index,
                name.c_str(), (void *)address, (int)address, (int)length);

        if (name == "code")
        {
            code_address = address;
        }
        if (name == "symb")
        {
            symb_address = address;
            symb_length  = length;
            has_symbols  = true;
        }
        if (name == "fext")
        {
            func_address  = address;
            func_length   = length;
            has_functions = true;
        }
        if (name == "clas")
        {
            classes_address = address;
            classes_length  = length;
            has_classes     = true;
        }

        if (name == "cove")
        {
            read_coverage_files(instructions, address, length);
        }
    }

    if (has_symbols)
    {
        read_symbols(instructions, symb_address, symb_length, offset);
    }

    if (has_classes)
    {
        read_classes(instructions, classes_address, classes_length);
    }

    if (has_functions)
    {
        read_functions_ex(instructions, func_address, func_length, offset);
    }

    this->last_ring_offset = offset;

    fprintf(stderr, "vm: seek initial code pointer to %d\n", (int)code_address);
    instructions.seek(code_address);
}

void DabVM::read_classes(Stream &input, uint64_t classes_address, uint64_t classes_length)
{
    // auto class_len = 2 + 2 + 2 + 2; // uint16 + uint16 + uint16 + uint16 + var

    // auto n_class = classes_length / class_len;

    fprintf(stderr, "classad=%p\n",
            // classlen=%d n_class=%d\n",
            (void *)classes_address
            //    (int)classes_length, (int)n_class);
    );

    auto address = classes_address;

    while (true) // for (size_t i = 0; i < n_class; i++)
    {
        auto class_index_address        = address;
        auto parent_class_index_address = class_index_address + 2;
        auto symbol_address             = parent_class_index_address + 2;
        auto template_num_address       = symbol_address + 2;

        auto class_index        = input.uint16_data(class_index_address);
        auto parent_class_index = input.uint16_data(parent_class_index_address);
        auto symbol             = input.uint16_data(symbol_address);
        auto template_num       = input.uint16_data(template_num_address);

        fprintf(stderr, "[class] index=%d parent=%d symbol=%d template=%d\n", (int)class_index,
                (int)parent_class_index, (int)symbol, (int)template_num);

        auto symbol_str = get_symbol(symbol);

        if (options.verbose)
        {
            fprintf(stderr, "vm/debug: class %d [parent=%d]: '%s'\n", (int)class_index,
                    (int)parent_class_index, symbol_str.c_str());
        }

        add_class(symbol_str, class_index, parent_class_index);

        address += 8 + 2 * template_num;

        if (address - classes_address == classes_length)
            break;
    }
}

struct MethodArgData
{
    uint16_t symbol_index;
    uint16_t class_index;
};

void DabVM::read_functions_ex(Stream &input, uint64_t func_address, uint64_t func_length,
                              uint64_t offset)
{
    auto fun_len = 2 + 2 + 8 + 2 + 8 + 1; // uint16 + uint16 + uint64 + uint16 + uint64 + uint8
    auto arg_len = 2 + 2;                 // uint16 + uint16

    auto ptr     = func_address;
    auto end_ptr = func_address + func_length;

    auto fun_index = 0;

    while (ptr < end_ptr)
    {
        auto symbol_address        = ptr;
        auto class_index_address   = symbol_address + 2;
        auto address_address       = class_index_address + 2;
        auto arg_count_address     = address_address + 8;
        auto method_length_address = arg_count_address + 2;
        auto method_flags_address  = method_length_address + 8;

        ptr += fun_len;

        auto symbol        = input.uint16_data(symbol_address);
        auto class_index   = input.uint16_data(class_index_address);
        auto address       = input.uint64_data(address_address);
        auto arg_count     = input.uint16_data(arg_count_address);
        auto method_length = input.uint64_data(method_length_address);
        auto flags         = input.uint8_data(method_flags_address);

        auto symbol_str = get_symbol(symbol);

        if (options.verbose)
        {
            fprintf(stderr, "vm/debug: func %d: '%s' at %p (class %d) (length %d) with %d args\n",
                    (int)fun_index, symbol_str.c_str(), (void *)address, (int)class_index,
                    (int)method_length, (int)arg_count);
        }
        auto data = (MethodArgData *)(input.raw_base_data() + ptr);

        ptr += arg_len * (arg_count + 1);

        bool is_static = flags == 1; // TODO!

        auto &function       = add_function(address, symbol_str, class_index, is_static);
        function.source_ring = offset;

        function.flags = flags;

        if (options.verbose)
        {
            // fprintf(stderr, "vm/debug: func offset is <%d>\n", (int)function.source_ring);
        }

        function.length = method_length;

        auto &reflection = function.reflection;
        reflection.arg_names.resize(arg_count);
        reflection.arg_klasses.resize(arg_count);
        reflection.ret_klass = data[arg_count].class_index;

        if (options.verbose)
        {
            // fprintf(stderr, "vm: describe %s:\n", symbol_str.c_str());
            // fprintf(stderr, "vm:   return: %s\n", classes[reflection.ret_klass].name.c_str());
        }

        for (size_t i = 0; i < arg_count; i++)
        {
            auto klass                    = data[i].class_index;
            auto name                     = get_symbol(data[i].symbol_index);
            auto arg_i                    = i;
            reflection.arg_klasses[arg_i] = klass;
            reflection.arg_names[arg_i]   = name;

            if (options.verbose)
            {
                // fprintf(stderr, "vm:   arg[%d]: %s '%s'\n", (int)arg_i,
                // classes[klass].name.c_str(),
                //         name.c_str());
            }
        }

        fun_index++;
    }
}

void DabVM::read_symbols(Stream &input, uint64_t symb_address, uint64_t symb_length,
                         uint64_t offset)
{
    /*
        fprintf(stderr, "Q intructions length %" PRIu64 " input %" PRIu64 "\n",
       instructions.length(), input.length());

        fprintf(stderr, "readbin: symbad=%p (%" PRIu64 ") symblen=%d\n", (void *)symb_address,
                symb_address, (int)symb_length);
    */

    const auto symbol_len = sizeof(uint64_t);

    auto n_symbols = symb_length / symbol_len;

    fprintf(stderr, "readbin: %" PRIu64 " symbol(s) to read\n", n_symbols);

    for (uint64_t i = 0; i < n_symbols; i++)
    {
        auto address = symb_address + i * symbol_len;
        // fprintf(stderr, "readbin: symbol x[%" PRIu64 "] -> address = %" PRIu64 "\n", i, address);
        auto ptr = input.uint64_data(address);
        // fprintf(stderr, "readbin: symbol x[%" PRIu64 "] -> ptr     = %" PRIu64 "\n", i, ptr);
        auto str = input.cstring_data(ptr);

        DabSymbol symbol;
        symbol.source_ring = offset;
        symbol.value       = str;

        symbols.push_back(symbol);

        if (options.verbose)
        {
            fprintf(stderr, "vm/debug: read symbol %d [%d]: %" PRIu64 " -> %" PRIu64 " -> '%s'\n",
                    (int)i, (int)symbols.size() - 1, (uint64_t)address, ptr, str.c_str());
        }
    }
}

void DabVM::read_coverage_files(Stream &stream, uint64_t address, uint64_t length)
{
    auto size_of_cov_file    = sizeof(uint64_t);
    auto number_of_cov_files = length / size_of_cov_file;
    fprintf(stderr, "vm: %d cov files\n", (int)number_of_cov_files);
    for (size_t j = 0; j < number_of_cov_files; j++)
    {
        auto ptr    = address + size_of_cov_file * j;
        auto data   = stream.uint64_data(ptr);
        auto string = stream.cstring_data(data);
        fprintf(stderr, "vm: cov[%d] %p -> %p -> '%s'\n", (int)j, (void *)ptr, (void *)data,
                string.c_str());
        auto hash  = j + 1;
        auto fname = string;
        coverage.add_file(hash, fname);
    }
}
