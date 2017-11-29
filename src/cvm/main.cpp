#include "cvm.h"

#include "../cshared/opcodes.h"
#include "../cshared/opcodes_format.h"
#include "../cshared/opcodes_debug.h"

DabVM *$VM = nullptr;

enum
{
    KERNEL_PRINT    = 0x00,
    KERNEL_EXIT     = 0x01,
    KERNEL_USECOUNT = 0x02,
    KERNEL_TOSYM    = 0x03,
};

DabVM::DabVM()
{
    fprintf(stderr, "vm: creating VM\n");
    assert(!$VM);
    $VM = this;
    predefine_default_classes();
    fprintf(stderr, "vm: VM created!\n");
}

DabVM::~DabVM()
{
    fprintf(stderr, "vm: VM destroyed!\n");
    shutdown = true;
}

DabVMReset::~DabVMReset()
{
    fprintf(stderr, "vm: reset $VM pointer\n");
    $VM = nullptr;
}

void DabVM::kernel_print(dab_register_t out_reg, std::vector<dab_register_t> reglist)
{
    assert(reglist.size() == 1);
    DabValue arg = register_get(reglist[0]);

    arg = cinstcall(arg, "to_s");

    if (options.verbose)
    {
        fprintf(stderr, "[ ");
        arg.print(stderr);
        fprintf(stderr, " ]\n");
    }
    if (!options.coverage_testing)
    {
        arg.print(options.output);
        fflush(options.output);
    }

    register_set(out_reg, nullptr);
}

bool DabVM::pop_frame(bool regular)
{
    if (options.verbose)
    {
        fprintf(stderr, "vm: pop %sframe\n", regular ? "regular " : "");
    }

    size_t frame_loc = frame_position;
    int    n_args    = number_of_args();
    size_t prev_pos  = prev_frame_position();
    auto   retval    = get_retval();
    auto   prev_ip   = get_prev_ip();
    auto   out_reg   = get_out_reg();

    stack.resize(frame_loc - 2 - n_args);

    frame_position = prev_pos;

    if (regular)
    {
        if (prev_pos != (size_t)-1)
        {
            if (out_reg.nil())
            {
                stack.push(retval);
            }
        }
        if (options.verbose)
        {
            fprintf(stderr, "vm: seek ret to %p (%d).\n", (void *)prev_ip, (int)prev_ip);
        }
        instructions.seek(prev_ip);
    }

    _registers = _register_stack.back();
    _register_stack.pop_back();

    if (!out_reg.nil())
    {
        if (options.verbose)
        {
            fprintf(stderr, "vm: set retval at 0x%x\n", out_reg.value());
        }
        register_set(out_reg, retval);
    }

    if (prev_pos == (size_t)-1)
    {
        if (options.verbose)
        {
            fprintf(stderr, "vm: pop last frame prev_ip = %zu\n", prev_ip);
        }
        return false;
    }

    return true;
}

size_t DabVM::stack_position() const
{
    return stack.size();
}

void DabVM::push_new_frame(bool use_self, const DabValue &self, int n_args, uint64_t block_addr,
                           dab_register_t out_reg, const DabValue &capture,
                           std::vector<dab_register_t> reglist, bool skip_stack_push)
{
    if (!skip_stack_push)
    {
        for (auto reg : reglist)
        {
            stack.push(register_get(reg));
        }
        if (use_self)
        {
            stack.push_value(self);
        }
    }
    stack.push((uint64_t)ip());
    stack.push((uint64_t)frame_position); // push previous frame
    frame_position = stack_position();
    stack.push((uint64_t)n_args); // number of arguments
    stack.push(self);
    stack.push(block_addr);
    stack.push(capture);
    stack.push((uint64_t)(out_reg.value()));
    {
        // push retvalue
        DabValue val;
        val.data.type = TYPE_INVALID;
        stack.push_value(val);
    }
    _register_stack.push_back(_registers);
    _registers.resize(0);
}

void DabVM::_dump(const char *name, const std::vector<DabValue> &data, FILE *output)
{
    fprintf(output, "Dump of %s:\n", name);
    for (size_t i = 0; i < data.size(); i++)
    {
        fprintf(output, "[%4zu] ", i);
        data[i].dump(output);
        fprintf(output, "\n");
    }
}

size_t DabVM::ip() const
{
    return instructions.position();
}

void DabVM::read_coverage_files(Stream &stream, size_t address, size_t length)
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

int DabVM::run_newformat(Stream &input)
{
    instructions.append(input);
    input.seek(0);

    if (!options.bare)
    {
        DabVM::load_newformat(input);
    }

    define_defaults();

    if (options.raw)
    {
        execute(instructions);
    }

    return continue_run(input);
}

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
    assert(version == 2);

    auto size_of_header     = input.read_uint64();
    auto size_of_data       = input.read_uint64();
    auto number_of_sections = input.read_uint64();

    fprintf(stderr, "vm: newformat: h: %d, d: %d, s: %d\n", (int)size_of_header, (int)size_of_data,
            (int)number_of_sections);

    size_t code_address = 0;
    size_t symb_address = 0;
    size_t symb_length  = 0;
    bool   has_symbols  = false;

    size_t func_address  = 0;
    size_t func_length   = 0;
    bool   has_functions = false;
    bool   functions_ex  = false;

    size_t classes_address = 0;
    size_t classes_length  = 0;
    bool   has_classes     = false;

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
        if (name == "data")
        {
            data_address = address;
        }
        if (name == "func" || name == "fext")
        {
            func_address  = address;
            func_length   = length;
            has_functions = true;
            functions_ex  = name == "fext";
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
        read_symbols(instructions, symb_address, symb_length, data_address);
    }

    if (has_classes)
    {
        read_classes(instructions, classes_address, classes_length);
    }

    if (has_functions)
    {
        if (functions_ex)
        {
            read_functions_ex(instructions, func_address, func_length);
        }
        else
        {
            read_functions(instructions, func_address, func_length);
        }
    }

    fprintf(stderr, "vm: seek initial code pointer to %d\n", (int)code_address);
    instructions.seek(code_address);
}

void DabVM::read_classes(Stream &input, size_t classes_address, size_t classes_length)
{
    auto class_len = 2 + 2 + 2; // uint16 + uint16 + uint16

    auto n_class = classes_length / class_len;

    fprintf(stderr, "classad=%p classlen=%d n_class=%d\n", (void *)classes_address,
            (int)classes_length, (int)n_class);

    for (size_t i = 0; i < n_class; i++)
    {
        auto class_index_address        = classes_address + i * class_len;
        auto parent_class_index_address = class_index_address + 2;
        auto symbol_address             = parent_class_index_address + 2;

        auto class_index        = input.uint16_data(class_index_address);
        auto parent_class_index = input.uint16_data(parent_class_index_address);
        auto symbol             = input.uint16_data(symbol_address);

        auto symbol_str = get_symbol(symbol);

        if (options.verbose)
        {
            fprintf(stderr, "vm/debug: class %d [parent=%d]: '%s'\n", (int)class_index,
                    (int)parent_class_index, symbol_str.c_str());
        }

        add_class(symbol_str, class_index, parent_class_index);
    }
}

void DabVM::read_functions(Stream &input, size_t func_address, size_t func_length)
{
    auto fun_len = 2 + 2 + 8; // uint16 + uint16 + uint64

    auto n_func = func_length / fun_len;

    fprintf(stderr, "funcad=%p funclen=%d n_func=%d\n", (void *)func_address, (int)func_length,
            (int)n_func);

    for (size_t i = 0; i < n_func; i++)
    {
        auto symbol_address      = func_address + i * fun_len;
        auto class_index_address = symbol_address + 2;
        auto address_address     = class_index_address + 2;

        auto symbol      = input.uint16_data(symbol_address);
        auto class_index = input.uint16_data(class_index_address);
        auto address     = input.uint64_data(address_address);

        auto symbol_str = get_symbol(symbol);

        if (options.verbose)
        {
            fprintf(stderr, "vm/debug: func %d: %d -> '%s' at %p (class %d)\n", (int)i, (int)symbol,
                    symbol_str.c_str(), (void *)address, (int)class_index);
        }

        add_function(address, symbol_str, class_index);
    }
}

struct MethodArgData
{
    uint16_t symbol_index;
    uint16_t class_index;
};

void DabVM::read_functions_ex(Stream &input, size_t func_address, size_t func_length)
{
    auto fun_len = 2 + 2 + 8 + 2; // uint16 + uint16 + uint64 + uint16
    auto arg_len = 2 + 2;         // uint16 + uint16

    auto ptr     = func_address;
    auto end_ptr = func_address + func_length;

    auto fun_index = 0;

    while (ptr < end_ptr)
    {
        auto symbol_address      = ptr;
        auto class_index_address = symbol_address + 2;
        auto address_address     = class_index_address + 2;
        auto arg_count_address   = address_address + 8;

        ptr += fun_len;

        auto symbol      = input.uint16_data(symbol_address);
        auto class_index = input.uint16_data(class_index_address);
        auto address     = input.uint64_data(address_address);
        auto arg_count   = input.uint16_data(arg_count_address);

        auto symbol_str = get_symbol(symbol);

        if (options.verbose)
        {
            fprintf(stderr, "vm/debug: func %d: '%s' at %p (class %d) with %d args\n",
                    (int)fun_index, symbol_str.c_str(), (void *)address, (int)class_index,
                    (int)arg_count);
        }
        auto data = (MethodArgData *)(input.raw_base_data() + ptr);

        ptr += arg_len * (arg_count + 1);

        auto &function = add_function(address, symbol_str, class_index);

        auto &reflection = function.reflection;
        reflection.arg_names.resize(arg_count);
        reflection.arg_klasses.resize(arg_count);
        reflection.ret_klass = data[arg_count].class_index;

        if (options.verbose)
        {
            fprintf(stderr, "vm: describe %s:\n", symbol_str.c_str());
            fprintf(stderr, "vm:   return: %s\n", classes[reflection.ret_klass].name.c_str());
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
                fprintf(stderr, "vm:   arg[%d]: %s '%s'\n", (int)arg_i, classes[klass].name.c_str(),
                        name.c_str());
            }
        }

        fun_index++;
    }
}

void DabVM::read_symbols(Stream &input, size_t symb_address, size_t symb_length,
                         size_t data_address)
{
    (void)data_address;

    fprintf(stderr, "symbad=%p symblen=%d data_address=%p\n", (void *)symb_address,
            (int)symb_length, (void *)data_address);
    const auto symbol_len = sizeof(uint64_t);

    auto n_symbols = symb_length / symbol_len;

    for (size_t i = 0; i < n_symbols; i++)
    {
        auto address = symb_address + i * symbol_len;
        auto ptr     = input.uint64_data(address);
        auto str     = input.cstring_data(ptr);
        symbols.push_back(str);
    }
}

int DabVM::run(Stream &input)
{
    return run_newformat(input);
}

int DabVM::continue_run(Stream &input)
{
    (void)input;

    if (!options.raw)
    {
        if (options.with_attributes)
        {
            fprintf(stderr, "vm: initialize attributes\n");
            instructions.rewind();
            call(dab_register_t::nilreg(), get_symbol_index("__init"), 0, DAB_SYMBOL_NIL, nullptr);
            execute(instructions);
        }
        instructions.rewind();
        call(dab_register_t::nilreg(), get_symbol_index("main"), 0, DAB_SYMBOL_NIL, nullptr);
        if (options.autorun)
        {
            execute(instructions);
        }
        else
        {
            execute_debug(instructions);
        }
    }

    return 0;
}

DabValue &DabVM::get_arg(int arg_index)
{
    auto index = frame_position - number_of_args() - 2 + arg_index;
    return stack[index];
}

DabValue &DabVM::get_retval()
{
    auto index = frame_position + 5;
    return stack[index];
}

uint64_t DabVM::get_block_addr()
{
    auto index = frame_position + 2;
    return stack[index].data.fixnum;
}

DabValue DabVM::get_block_capture()
{
    auto index = frame_position + 3;
    return stack[index];
}

dab_register_t DabVM::get_out_reg()
{
    auto index = frame_position + 4;
    auto ret   = stack[index].data.fixnum;
    return ret;
}

DabValue &DabVM::get_self()
{
    auto index = frame_position + 1;
    return stack[index];
}

size_t DabVM::get_prev_ip()
{
    return stack[frame_position - 2].data.fixnum;
}

size_t DabVM::prev_frame_position()
{
    return stack[frame_position - 1].data.fixnum;
}

int DabVM::number_of_args()
{
    return (int)stack[frame_position + 0].data.fixnum;
}

void DabVM::call(dab_register_t out_reg, dab_symbol_t symbol, int n_args, dab_symbol_t block_symbol,
                 const DabValue &capture, std::vector<dab_register_t> reglist)
{
    if (options.verbose)
    {
        auto name       = get_symbol(symbol);
        auto block_name = get_symbol(block_symbol);
        fprintf(stderr, "vm: call <%s> with %d arguments and <%s> block.\n", name.c_str(), n_args,
                block_name.c_str());
    }
    if (!functions.count(symbol))
    {
        auto name = get_symbol(symbol);
        fprintf(stderr, "vm error: Unknown function <%s>.\n", name.c_str());
        exit(1);
    }
    if (block_symbol != DAB_SYMBOL_NIL)
    {
        auto &blockfun = functions[block_symbol];
        assert(blockfun.regular);
        _call_function(false, out_reg, nullptr, functions[symbol], n_args, (void *)blockfun.address,
                       capture, reglist);
    }
    else
    {
        _call_function(false, out_reg, nullptr, functions[symbol], n_args, nullptr, nullptr,
                       reglist);
    }
}

void DabVM::_call_function(bool use_self, dab_register_t out_reg, const DabValue &self,
                           const DabFunction &fun, int n_args, void *blockaddress,
                           const DabValue &capture, std::vector<dab_register_t> reglist,
                           DabValue *return_value, size_t stack_pos, bool skip_stack_push)
{
    (void)return_value;
    (void)stack_pos;

    if (options.verbose)
    {
        fprintf(stderr, "vm: call <%s> %sand %d arguments -> 0x%x.\n", fun.name.c_str(),
                blockaddress ? "with block " : "", n_args, out_reg.value());
    }

    if (fun.regular)
    {
        push_new_frame(use_self, self, n_args, (uint64_t)blockaddress, out_reg, capture, reglist,
                       skip_stack_push);
        instructions.seek(fun.address);

        if (return_value)
        {
            // temporary hack
            while (stack.size() != stack_pos)
            {
                execute_single(instructions);
            }

            *return_value = stack.pop_value();
        }
    }
    else if (fun.extra_reg)
    {
        std::vector<DabValue> value_list;
        for (auto reg : reglist)
        {
            value_list.push_back(register_get(reg));
        }
        auto out = fun.extra_reg(use_self ? self : DabValue(nullptr), value_list);
        register_set(out_reg, out);
        if (return_value)
        {
            *return_value = out;
        }
    }
}

void DabVM::execute(Stream &input)
{
    while (!input.eof())
    {
        if (!execute_single(input))
        {
            break;
        }
        if (breakpoints.count(ip()))
        {
            return;
        }
    }
}

DabValue DabVM::register_get(dab_register_t reg)
{
    auto reg_index = reg.value();
    if (reg.nil() || _registers.size() <= reg_index)
    {
        return nullptr;
    }
    return _registers[reg_index];
}

void DabVM::register_set(dab_register_t reg, const DabValue &value)
{
    auto reg_index = reg.value();
    if (reg.nil())
    {
        return;
    }

    if (_registers.size() <= reg_index)
    {
        _registers.resize(reg_index + 1);
    }
    _registers[reg_index] = value;
}

void DabVM::reflect(size_t reflection_type, const DabValue &symbol, bool out_reg,
                    dab_register_t reg, bool has_class, uint16_t class_index)
{
    switch (reflection_type)
    {
    case REFLECT_METHOD_ARGUMENTS:
    case REFLECT_METHOD_ARGUMENT_NAMES:
        reflect_method_arguments(reflection_type, symbol, out_reg, reg);
        break;
    case REFLECT_INSTANCE_METHOD_ARGUMENT_TYPES:
    case REFLECT_INSTANCE_METHOD_ARGUMENT_NAMES:
        reflect_instance_method(reflection_type, symbol, out_reg, reg, has_class, class_index);
        break;
    default:
        fprintf(stderr, "vm: unknown reflection %d\n", (int)reflection_type);
        exit(1);
        break;
    }
}

void DabVM::reflect_method_arguments(size_t reflection_type, const DabValue &symbol, bool out_reg,
                                     dab_register_t reg)
{
    if (options.verbose)
    {
        fprintf(stderr, "vm: reflect %d on %s\n", (int)reflection_type, symbol.string().c_str());
    }
    auto        func_index = get_or_create_symbol_index(symbol.string());
    const auto &function   = functions[func_index];

    auto output_names = reflection_type == REFLECT_METHOD_ARGUMENT_NAMES;
    _reflect(function, out_reg, reg, output_names);
}

void DabVM::reflect_instance_method(size_t reflection_type, const DabValue &symbol, bool out_reg,
                                    dab_register_t reg, bool has_class, uint16_t class_index)
{
    assert(has_class);

    auto &klass = get_class(class_index);
    if (options.verbose)
    {
        fprintf(stderr, "vm: reflect %d on %s [%s]\n", (int)reflection_type,
                symbol.string().c_str(), klass.name.c_str());
    }
    const auto &function = klass.get_instance_function(symbol.string());

    auto output_names = reflection_type == REFLECT_INSTANCE_METHOD_ARGUMENT_NAMES;
    _reflect(function, out_reg, reg, output_names);
}

void DabVM::_reflect(const DabFunction &function, bool out_reg, dab_register_t reg,
                     bool output_names)
{
    const auto &reflection = function.reflection;

    auto n = reflection.arg_names.size();

    DabValue array_class = classes[CLASS_ARRAY];
    DabValue value       = array_class.create_instance();
    auto &   array       = value.array();
    array.resize(n);

    if (options.verbose)
    {
        fprintf(stderr, "vm: reflect %d arguments\n", (int)n);
    }

    for (size_t i = 0; i < n; i++)
    {
        DabValue value;
        if (output_names)
        {
            value = DabValue(reflection.arg_names[i]);
        }
        else
        {
            auto index = reflection.arg_klasses[i];
            value      = DabValue(classes[index]);
        }
        array[i] = value;
    }

    if (out_reg)
    {
        register_set(reg, value);
    }
    else
    {
        stack.push_value(value);
    }
}

bool DabVM::execute_single(Stream &input)
{
    auto pos    = input.position();
    auto opcode = input.read_uint8();
    if (options.verbose)
    {
        fprintf(stderr, "@ %d: %d [%s]\n", (int)pos, (int)opcode, g_opcodes[opcode].name.c_str());
    }
    switch (opcode)
    {
    case OP_LOAD_METHOD:
    {
        auto out_reg    = input.read_reg();
        auto symbol     = input.read_symbol();
        auto symbol_str = get_symbol(symbol);
        push_method(symbol_str);
        auto value = stack.pop_value();
        register_set(out_reg, value);
        break;
    }
    case OP_NEW_ARRAY:
    {
        auto out_reg = input.read_reg();
        auto reglist = input.read_reglist();

        auto n = reglist.size();

        DabValue array_class = classes[CLASS_ARRAY];
        DabValue value       = array_class.create_instance();
        auto &   array       = value.array();
        array.resize(n);
        for (size_t i = 0; i < n; i++)
        {
            array[i] = register_get(reglist[i]);
        }
        register_set(out_reg, value);

        break;
    }
    case OP_CALL:
    {
        auto out_reg = input.read_reg();
        auto symbol  = input.read_symbol();
        auto reglist = input.read_reglist();
        call(out_reg, symbol, (int)reglist.size(), DAB_SYMBOL_NIL, nullptr, reglist);
        break;
    }
    case OP_CALL_BLOCK:
    {
        auto out_reg      = input.read_reg();
        auto symbol       = input.read_symbol();
        auto block_symbol = input.read_symbol();
        auto capture_reg  = input.read_reg();
        auto capture      = register_get(capture_reg);
        auto reglist      = input.read_reglist();

        call(out_reg, symbol, (int)reglist.size(), block_symbol, capture, reglist);
        break;
    }
    case OP_INSTCALL_BLOCK:
    {
        auto out_reg  = input.read_reg();
        auto self_reg = input.read_reg();
        auto symbol   = input.read_uint16();
        auto name     = get_symbol(symbol);

        auto block_symbol = input.read_symbol();
        auto block_name   = get_symbol(block_symbol);
        auto capture_reg  = input.read_reg();
        auto capture      = register_get(capture_reg);

        auto reglist = input.read_reglist();
        auto n_args  = reglist.size();
        auto recv    = register_get(self_reg);

        instcall(recv, name, n_args, block_name, capture, out_reg, reglist);
        break;
    }
    case OP_YIELD:
    {
        auto out_reg = input.read_reg();

        auto reglist = input.read_reglist();

        auto n_args = reglist.size();

        auto self = get_self();
        auto addr = get_block_addr();

        if (options.verbose)
        {
            fprintf(stderr, "vm: yield to %p with %d arguments.\n", (void *)addr, (int)n_args);
            fprintf(stderr, "vm: capture data is ");
            get_block_capture().dump(stderr);
            fprintf(stderr, ".\n");
        }

        push_new_frame(false, self, (int)n_args, 0, out_reg, get_block_capture(), reglist);
        instructions.seek(addr);

        break;
    }
    case OP_LOAD_CLOSURE:
    {
        auto reg_index     = input.read_reg();
        auto closure_index = input.read_uint16();
        auto closure       = get_block_capture();
        assert(closure.data.type == TYPE_ARRAY);
        auto &array = closure.array();
        if (options.verbose)
        {
            fprintf(stderr, "vm: get captured var %d (of %lu).\n", closure_index, array.size());
        }
        auto value = array[closure_index];
        register_set(reg_index, value);
        break;
    }
    case OP_LOAD_STRING:
    {
        auto reg_index = input.read_reg();
        auto address   = input.read_uint64();
        auto length    = input.read_uint64();

        auto &klass        = get_class(CLASS_LITERALSTRING);
        auto  klass_object = DabValue(klass);

        auto instance = klass_object.create_instance();

        auto data = dynamic_cast<DabLiteralString *>(instance.data.object->object);

        data->pointer = instructions.string_ptr(address);
        data->length  = length;

        register_set(reg_index, instance);
        break;
    }
    case OP_LOAD_SELF:
    {
        auto reg_index = input.read_reg();
        register_set(reg_index, get_self());
        break;
    }
    case OP_LOAD_TRUE:
    {
        auto reg_index = input.read_reg();
        register_set(reg_index, DabValue(true));
        break;
    }
    case OP_LOAD_FALSE:
    {
        auto reg_index = input.read_reg();
        register_set(reg_index, DabValue(false));
        break;
    }
    case OP_LOAD_HAS_BLOCK:
    {
        auto reg_index = input.read_reg();
        auto addr      = get_block_addr();
        register_set(reg_index, DabValue(addr != 0));
        break;
    }
    case OP_LOAD_NUMBER:
    {
        auto reg_index = input.read_reg();
        auto number    = input.read_uint64();
        register_set(reg_index, DabValue(number));
        break;
    }
    case OP_REFLECT:
    {
        auto reg_index       = input.read_reg();
        auto symbol_index    = input.read_symbol();
        auto reflection_type = input.read_uint16();
        auto symbol          = get_symbol(symbol_index);

        uint16_t class_index = input.read_uint16();

        reflect(reflection_type, symbol, true, reg_index, true, class_index);
        break;
    }
    case OP_LOAD_INT8:
    {
        auto     reg_index = input.read_reg();
        auto     n         = input.read_int8();
        DabValue value(CLASS_INT8, n);
        register_set(reg_index, value);
        break;
    }
    case OP_LOAD_INT16:
    {
        auto     reg_index = input.read_reg();
        auto     n         = input.read_int16();
        DabValue value(CLASS_INT16, n);
        register_set(reg_index, value);
        break;
    }
    case OP_LOAD_INT32:
    {
        auto     reg_index = input.read_reg();
        auto     n         = input.read_int32();
        DabValue value(CLASS_INT32, n);
        register_set(reg_index, value);
        break;
    }
    case OP_LOAD_UINT8:
    {
        auto     reg_index = input.read_reg();
        auto     n         = input.read_uint8();
        DabValue value(CLASS_UINT8, n);
        register_set(reg_index, value);
        break;
    }
    case OP_LOAD_UINT16:
    {
        auto     reg_index = input.read_reg();
        auto     n         = input.read_uint16();
        DabValue value(CLASS_UINT16, n);
        register_set(reg_index, value);
        break;
    }
    case OP_LOAD_UINT32:
    {
        auto     reg_index = input.read_reg();
        auto     n         = input.read_uint32();
        DabValue value(CLASS_UINT32, n);
        register_set(reg_index, value);
        break;
    }
    case OP_LOAD_UINT64:
    {
        auto     reg_index = input.read_reg();
        auto     n         = input.read_uint64();
        DabValue value(CLASS_UINT64, n);
        register_set(reg_index, value);
        break;
    }
    case OP_LOAD_INT64:
    {
        auto     reg_index = input.read_reg();
        auto     n         = input.read_int64();
        DabValue value(CLASS_INT64, n);
        register_set(reg_index, value);
        break;
    }
    case OP_LOAD_NIL:
    {
        auto reg_index = input.read_reg();
        register_set(reg_index, nullptr);
        break;
    }
    case OP_LOAD_ARG:
    {
        auto reg_index = input.read_reg();
        auto arg_index = input.read_uint16();
        auto var       = get_arg(arg_index);
        register_set(reg_index, var);
        break;
    }
    case OP_LOAD_CLASS:
    {
        auto reg_index   = input.read_reg();
        auto klass_index = input.read_uint16();
        auto klass       = classes[klass_index];
        register_set(reg_index, klass);
        break;
    }
    case OP_MOV:
    {
        auto dst_index = input.read_reg();
        auto src_index = input.read_reg();
        register_set(dst_index, register_get(src_index));
        break;
    }
    case OP_RETURN:
    {
        auto  reg_index = input.read_reg();
        auto  value     = register_get(reg_index);
        auto &retval    = get_retval();
        retval          = value;
        if (!pop_frame(true))
        {
            return false;
        }
        break;
    }
    case OP_JMP:
    {
        auto mod         = input.read_int16() - 3;
        auto new_address = ip() + mod;
        if (options.verbose)
        {
            fprintf(stderr, "JMP(%d), new address: %p -> %p\n", mod, (void *)ip(),
                    (void *)new_address);
        }
        instructions.seek(new_address);
        break;
    }
    case OP_JMP_IF:
    {
        auto value_reg = input.read_reg();
        auto mod_true  = input.read_int16() - 7;
        auto mod_false = input.read_int16() - 7;
        auto value     = register_get(value_reg);
        auto test      = value.truthy();
        instructions.seek(ip() + (test ? mod_true : mod_false));
        break;
    }
    case OP_NOP:
    {
        break;
    }
    case OP_SYSCALL:
    {
        auto reg     = input.read_reg();
        auto call    = input.read_uint8();
        auto reglist = input.read_reglist();
        kernelcall(reg, call, reglist);
        break;
    }
    case OP_INSTCALL:
    {
        auto out_reg  = input.read_reg();
        auto self_reg = input.read_reg();
        auto symbol   = input.read_uint16();
        auto name     = get_symbol(symbol);
        auto reglist  = input.read_reglist();
        auto n_args   = reglist.size();
        auto recv     = register_get(self_reg);
        if (options.verbose)
        {
            fprintf(stderr, "vm: instcall, recv = ");
            recv.dump(stderr);
            fprintf(stderr, "\n");
        }
        instcall(recv, name, n_args, "", nullptr, out_reg, reglist);
        break;
    }
    case OP_GET_INSTVAR:
    {
        auto out_reg = input.read_reg();
        auto symbol  = input.read_symbol();
        auto name    = get_symbol(symbol);
        get_instvar(name, true, out_reg);
        break;
    }
    case OP_SET_INSTVAR:
    {
        auto symbol = input.read_symbol();
        auto reg    = input.read_reg();
        auto name   = get_symbol(symbol);
        auto value  = register_get(reg);
        set_instvar(name, value);
        break;
    }
    case OP_STACK_RESERVE:
    {
        auto n = input.read_uint16();
        assert(n == 0);
        break;
    }
    case OP_COV:
    {
        auto hash = input.read_uint16();
        auto line = input.read_uint16();
        coverage.add_line(hash, line);
        break;
    }
    case OP_RELEASE:
    {
        auto reg   = input.read_reg();
        auto value = register_get(reg);
        value.release();
        register_set(reg, nullptr);
        break;
    }
    case OP_RETAIN:
    {
        auto reg   = input.read_reg();
        auto value = register_get(reg);
        value.retain();
        break;
    }
    case OP_CAST:
    {
        auto dst_reg     = input.read_reg();
        auto src_reg     = input.read_reg();
        auto klass_index = input.read_uint16();

        auto src = register_get(src_reg);
        auto dst = cast(src, klass_index);

        register_set(dst_reg, dst);

        break;
    }
    default:
        fprintf(stderr, "VM error: Unknown opcode <%02x> (%d).\n", (int)opcode, (int)opcode);
        exit(1);
        break;
    }
    return true;
}

void DabVM::get_instvar(const std::string &name, bool use_out_reg, dab_register_t out_reg)
{
    auto value = get_self().get_instvar(name);
    if (use_out_reg)
    {
        register_set(out_reg, value);
    }
    else
    {
        stack.push_value(value);
    }
}

void DabVM::set_instvar(const std::string &name, const DabValue &value)
{
    get_self().set_instvar(name, value);
}

DabValue DabVM::cast(const DabValue &value, int klass_index)
{
    auto from = value.class_index();
    auto to   = klass_index;

    if (from == to)
    {
        return value;
    }

    auto from_fixnum = from == CLASS_FIXNUM;
    auto to_fixnum   = to == CLASS_FIXNUM;

    if (from_fixnum && to == CLASS_UINT8)
    {
        return DabValue(to, (uint8_t)value.data.fixnum);
    }
    else if (from == CLASS_UINT8 && to_fixnum)
    {
        DabValue copy;
        copy.data.type   = TYPE_FIXNUM;
        copy.data.fixnum = value.data.num_uint8;
        return copy;
    }
    else if (from == CLASS_INT32 && to_fixnum)
    {
        DabValue copy;
        copy.data.type   = TYPE_FIXNUM;
        copy.data.fixnum = value.data.num_int32;
        return copy;
    }
    else if (from_fixnum && to == CLASS_UINT32)
    {
        return DabValue(to, (uint32_t)value.data.fixnum);
    }
    else if (from_fixnum && to == CLASS_UINT64)
    {
        return DabValue(to, (uint64_t)value.data.fixnum);
    }
    else if (from_fixnum && to == CLASS_INT8)
    {
        return DabValue(to, (int8_t)value.data.fixnum);
    }
    else if (from_fixnum && to == CLASS_INT16)
    {
        return DabValue(to, (int16_t)value.data.fixnum);
    }
    else if (from_fixnum && to == CLASS_INT32)
    {
        return DabValue(to, (int32_t)value.data.fixnum);
    }
    else if (from_fixnum && to == CLASS_INT64)
    {
        return DabValue(to, (int64_t)value.data.fixnum);
    }
    else if (from == CLASS_UINT32 && to == CLASS_INT32)
    {
        return DabValue(to, (int32_t)value.data.num_uint32);
    }
    else if (from == CLASS_INT32 && to == CLASS_UINT64)
    {
        return DabValue(to, (uint64_t)value.data.num_int32);
    }
    else if (from == CLASS_INT8 && to_fixnum)
    {
        DabValue copy;
        copy.data.type   = TYPE_FIXNUM;
        copy.data.fixnum = value.data.num_int8;
        return copy;
    }
    else if (from == CLASS_UINT32 && to_fixnum)
    {
        DabValue copy;
        copy.data.type   = TYPE_FIXNUM;
        copy.data.fixnum = value.data.num_uint32;
        return copy;
    }
    else if (from == CLASS_UINT64 && to_fixnum)
    {
        DabValue copy;
        copy.data.type   = TYPE_FIXNUM;
        copy.data.fixnum = value.data.num_uint64;
        return copy;
    }
    else if (from == CLASS_NILCLASS && to == CLASS_INTPTR)
    {
        DabValue copy;
        copy.data.type   = TYPE_INTPTR;
        copy.data.intptr = nullptr;
        return copy;
    }
    else if (from == CLASS_STRING && to == CLASS_INTPTR)
    {
        DabValue copy;
        copy.data.type   = TYPE_INTPTR;
        copy.data.intptr = (void *)value.string().c_str();
        return copy;
    }
    else if (from == CLASS_BYTEBUFFER && to == CLASS_INTPTR)
    {
        DabValue copy;
        copy.data.type   = TYPE_INTPTR;
        copy.data.intptr = &value.bytebuffer()[0];
        return copy;
    }
    else if (from == CLASS_INTPTR && to == CLASS_STRING)
    {
        DabValue copy;
        copy.data.type          = TYPE_STRING;
        copy.data.legacy_string = (const char *)value.data.intptr;
        return copy;
    }
    else if (from == CLASS_LITERALSTRING && to == CLASS_STRING)
    {
        DabValue copy;
        copy.data.type          = TYPE_STRING;
        copy.data.legacy_string = value.string();
        return copy;
    }
    else
    {
        char info[256];
        snprintf(info, sizeof(info), "cannot cast %s (%d) to %s (%d)", value.class_name().c_str(),
                 (int)value.class_index(), get_class(klass_index).name.c_str(), (int)klass_index);
        throw DabCastError(info);
    }
}

void DabVM::add_class(const std::string &name, int index, int parent_index)
{
    if (!classes.count(index))
    {
        auto &parent = classes[parent_index];
        fprintf(stderr, "vm: add class <%s> (parent = <%s>).\n", name.c_str(), parent.name.c_str());
        DabClass klass;
        klass.name             = name;
        klass.index            = index;
        klass.builtin          = false;
        klass.superclass_index = parent_index;
        classes[index]         = klass;
    }
}

DabValue DabVM::cinstcall(DabValue self, const std::string &name)
{
    auto stack_pos = stack.size() + 1;

    DabValue ret;
    instcall(self, name, 0, "", nullptr, -1, {}, &ret, stack_pos, true);
    return ret;
}

void DabVM::instcall(const DabValue &recv, const std::string &name, size_t n_args,
                     const std::string &block_name, const DabValue &capture, dab_register_t outreg,
                     std::vector<dab_register_t> reglist, DabValue *return_value, size_t stack_pos,
                     bool skip_stack_push)
{
    auto  class_index = recv.class_index();
    auto &klass       = get_class(class_index);
    stack.push_value(recv);

    bool  use_static_func = recv.data.type == TYPE_CLASS;
    auto &fun =
        use_static_func ? klass.get_static_function(name) : klass.get_instance_function(name);

    if (block_name != "")
    {
        auto  block_symbol = get_or_create_symbol_index(block_name);
        auto &blockfun     = functions[block_symbol];
        assert(blockfun.regular);
        _call_function(true, outreg, recv, fun, (int)(1 + n_args), (void *)blockfun.address,
                       capture, reglist, return_value, stack_pos, skip_stack_push);
    }
    else
    {
        _call_function(true, outreg, recv, fun, (int)(1 + n_args), nullptr, nullptr, reglist,
                       return_value, stack_pos, skip_stack_push);
    }
}

void DabVM::kernelcall(dab_register_t out_reg, int call, std::vector<dab_register_t> reglist)
{
    switch (call)
    {
    case KERNEL_PRINT:
    {
        kernel_print(out_reg, reglist);
        break;
    }
    case KERNEL_EXIT:
    {
        DabValue value;

        assert(reglist.size() == 1);
        value = register_get(reglist[0]);

        exit((int)value.data.fixnum);
        break;
    }
    case KERNEL_USECOUNT:
    {
        DabValue value;

        assert(reglist.size() == 1);
        value = register_get(reglist[0]);

        auto dab_value = uint64_t(value.use_count());

        register_set(out_reg, dab_value);
        break;
    }
    case KERNEL_TOSYM:
    {
        auto string_ob = cast(register_get(reglist[0]), CLASS_STRING);
        auto string    = string_ob.string();

        auto symbol_index = get_or_create_symbol_index(string);

        DabValue value(CLASS_FIXNUM, (uint64_t)symbol_index);

        register_set(out_reg, value);
        break;
    }
    default:
        fprintf(stderr, "VM error: Unknown kernel call <%d>.\n", (int)call);
        exit(1);
        break;
    }
}

size_t DabVM::get_or_create_symbol_index(const std::string &string)
{
    for (size_t i = 0; i < symbols.size(); i++)
    {
        auto &symbol = symbols[i];
        if (symbol == string)
        {
            return i;
        }
    }
    symbols.push_back(string);
    return symbols.size() - 1;
}

void DabVM::push_method(const std::string &name)
{
    DabValue val;
    val.data.type          = TYPE_METHOD;
    val.data.legacy_string = name;
    stack.push_value(val);
}

DabFunction &DabVM::add_function(size_t address, const std::string &name, uint16_t class_index)
{
    fprintf(stderr, "vm: add function <%s>.\n", name.c_str());
    DabFunction function;
    function.address = address;
    function.name    = name;
    auto func_index  = get_or_create_symbol_index(name);
    if (class_index == 0xFFFF)
    {

        functions[func_index] = function;
        return functions[func_index];
    }
    else
    {
        get_class(class_index).functions[func_index] = function;
        return get_class(class_index).functions[func_index];
    }
}

void DabVM::extract(const std::string &name)
{
    FILE *output = options.output;

    if (name == "rip")
    {
        printf("%zu", ip());
    }
    else if (name == "output")
    {
    }
    else if (name == "stack[-1]")
    {
        if (stack.size() == 0)
        {
            fprintf(stderr, "vm: empty stack.\n");
            exit(1);
        }
        stack[stack.size() - 1].dump(output);
    }
    else if (name == "leaktest")
    {
        run_leaktest(output);
    }
    else if (name == "reg[0]")
    {
        register_get(0).dump(output);
    }
    else if (name == "reg[1]")
    {
        register_get(1).dump(output);
    }
    else
    {
        fprintf(stderr, "vm: unknown extract option <%s>.\n", name.c_str());
        exit(1);
    }
}

bool DabVM::run_leaktest(FILE *output)
{
    bool error = false;
    if (stack.size() > 0)
    {
        fprintf(output, "leaktest: %zu items on stack\n", stack.size());
        for (size_t i = 0; i < stack.size(); i++)
        {
            fprintf(output, "%4zu: ", i);
            stack[i].dump(output);
            fprintf(output, "\n");
        }
        error = true;
    }
    if (DabMemoryCounter<COUNTER_OBJECT>::counter() > 0)
    {
        fprintf(output, "leaktest: %zu allocated objects remaining\n",
                DabMemoryCounter<COUNTER_OBJECT>::counter());
        error = true;
    }
    if (DabMemoryCounter<COUNTER_PROXY>::counter() > 0)
    {
        fprintf(output, "leaktest: %zu allocated proxies remaining\n",
                DabMemoryCounter<COUNTER_PROXY>::counter());
        error = true;
    }
    if (DabMemoryCounter<COUNTER_VALUE>::counter() > 0)
    {
        fprintf(output, "leaktest: %zu allocated values remaining\n",
                DabMemoryCounter<COUNTER_VALUE>::counter());
        error = true;
    }
    if (!error)
    {
        fprintf(output, "leaktest: no leaks\n");
    }
    return error;
}

void DabRunOptions::parse(const std::vector<std::string> &args)
{
    std::map<std::string, bool>        flags;
    std::map<std::string, std::string> options;
    std::vector<std::string> others;

    for (auto &arg : args)
    {
        if (arg.substr(0, 2) == "--")
        {
            auto pos = arg.find("=");
            if (pos != std::string::npos)
            {
                auto argname     = arg.substr(0, pos);
                auto argvalue    = arg.substr(pos + 1);
                options[argname] = argvalue;
                fprintf(stderr, "[%s]=[%s]\n", argname.c_str(), argvalue.c_str());
            }
            else
            {
                flags[arg] = true;
            }
        }
        else
        {
            others.push_back(arg);
        }
    }

    if (others.size() > 1)
    {
        fprintf(stderr, "vm: too many file arguments.\n");
        exit(1);
    }

    if (flags.count("--leaktest"))
    {
        this->leaktest = true;
    }

    if (options.count("--output"))
    {
        this->extract      = true;
        this->extract_part = options["--output"];
    }

    if (options.count("--out"))
    {
        this->output       = fopen(options["--out"].c_str(), "wb");
        this->close_output = true;
    }

    if (others.size() == 1)
    {
        auto filename = others[0].c_str();
        auto file     = fopen(filename, "rb");
        if (!file)
        {
            fprintf(stderr, "vm: cannot open file <%s> for reading!\n", filename);
            exit(1);
        }
        this->input      = file;
        this->close_file = true;
    }

    if (flags["--with-attributes"])
    {
        this->with_attributes = true;
    }

    if (flags["--verbose"])
    {
        this->verbose = true;
    }

    if (flags["--debug"])
    {
        this->autorun = false;
    }

    if (flags["--raw"])
    {
        this->raw = true;
    }

    if (flags["--bare"])
    {
        this->bare = true;
    }

    if (flags["--cov"])
    {
        this->coverage_testing = true;
    }

    if (flags["--noautorelease"] || flags["--no-autorelease"])
    {
        this->autorelease = false;
    }
}

int unsafe_main(int argc, char **argv)
{
    setup_handlers();

    DabVM          vm;
    DabRunOptions &options = vm.options;

    std::vector<std::string> args;
    for (int i = 1; i < argc; i++)
    {
        args.push_back(argv[i]);
    }
    options.parse(args);
    fprintf(stderr, "VM options: autorun %s raw %s cov %s\n", options.autorun ? "yes" : "no",
            options.raw ? "yes" : "no", options.coverage_testing ? "yes" : "no");

    Stream input;
    byte   buffer[1024];
    auto   stream = options.input;
    while (!feof(stream))
    {
        size_t bytes = fread(buffer, 1, 1024, stream);
        if (bytes)
        {
            input.append(buffer, bytes);
        }
    }

    auto ret_value = vm.run(input);

    auto clear_registers = [&vm]() {
        vm.symbols.resize(0);
        vm._registers.resize(0);
        vm._register_stack.resize(0);
    };
    auto leaktest = options.extract_part == "leaktest";
    if (leaktest)
    {
        clear_registers();
    }
    if (options.extract)
    {
        vm.extract(options.extract_part);
    }
    if (!leaktest)
    {
        clear_registers();
    }
    if (options.close_file)
    {
        fclose(stream);
    }
    if (options.coverage_testing)
    {
        vm.coverage.dump(stdout);
    }
    if (ret_value == 0 && options.leaktest)
    {
        bool leaked = vm.run_leaktest(options.output);
        if (leaked)
        {
            ret_value = 1;
        }
    }
    if (options.close_output)
    {
        fclose(options.output);
    }
    return ret_value;
}

int main(int argc, char **argv)
{
    try
    {
        return unsafe_main(argc, argv);
    }
    catch (DabRuntimeError &error)
    {
        fprintf(stderr, "vm: %s.\n", error.what());
        return 1;
    }
}
