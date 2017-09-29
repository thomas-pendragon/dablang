#include "cvm.h"

#include "../cshared/opcodes.h"

DabVM *$VM = nullptr;

enum
{
    KERNEL_PRINT    = 0x00,
    KERNEL_EXIT     = 0x01,
    KERNEL_USECOUNT = 0x02,
};

DabVM::DabVM()
{
    fprintf(stderr, "vm: creating VM\n");
    assert(!$VM);
    $VM = this;
    define_defaults();
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

void DabVM::kernel_print(bool use_out_reg, dab_register_t out_reg, bool use_reglist,
                         std::vector<dab_register_t> reglist, bool output_value)
{
    DabValue arg;
    auto     stack_pos = stack.size();
    if (!use_reglist)
    {
        arg = stack.pop_value();
    }
    else
    {
        assert(reglist.size() == 1);
        arg = register_get(reglist[0]);
        stack_pos += 1;
    }

    instcall(arg, "to_s", 0, 1);
    // temporary hack
    while (stack.size() != stack_pos)
    {
        execute_single(instructions);
    }
    arg = stack.pop_value();

    if (verbose)
    {
        fprintf(stderr, "[ ");
        arg.print(stderr);
        fprintf(stderr, " ]\n");
    }
    if (!coverage_testing)
    {
        arg.print(dab_output);
        fflush(dab_output);
    }

    if (!output_value)
        return;

    if (out_reg.nil())
    {
        if (!use_out_reg)
        {
            stack.push_nil();
        }
    }
    else
    {
        register_set(out_reg, nullptr);
    }
}

bool DabVM::pop_frame(bool regular)
{
    if (verbose)
    {
        fprintf(stderr, "vm: pop %sframe\n", regular ? "regular " : "");
    }

    int    frame_loc = frame_position;
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
        if (verbose)
        {
            fprintf(stderr, "vm: seek ret to %p (%d).\n", (void *)prev_ip, (int)prev_ip);
        }
        instructions.seek(prev_ip);
    }

    _registers = _register_stack.back();
    _register_stack.pop_back();

    if (!out_reg.nil())
    {
        if (verbose)
        {
            fprintf(stderr, "vm: set retval at 0x%x\n", out_reg.value());
        }
        register_set(out_reg, retval);
    }

    if (prev_pos == (size_t)-1)
    {
        if (verbose)
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
                           dab_register_t out_reg, const DabValue &capture, bool use_reglist,
                           std::vector<dab_register_t> reglist)
{
    if (use_reglist)
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

int DabVM::run(Stream &input, bool autorun, bool raw, bool coverage_testing)
{
    this->coverage_testing = coverage_testing;

    auto mark1 = input.read_uint8();
    auto mark2 = input.read_uint8();
    auto mark3 = input.read_uint8();
    if (mark1 != 'D' || mark2 != 'A' || mark3 != 'B')
    {
        fprintf(stderr, "VM error: invalid mark (%c%c%c, expected DAB).\n", (char)mark1,
                (char)mark2, (char)mark3);
        exit(1);
    }
    auto compiler_version = input.read_uint64();
    auto vm_version       = input.read_uint64();
    auto code_length      = input.read_uint64();
    auto code_crc         = input.read_uint64();

    (void)compiler_version;
    (void)vm_version;
    (void)code_length;
    (void)code_crc;

    instructions.append(input);

    execute(instructions);

    if (!raw)
    {
        if (with_attributes)
        {
            fprintf(stderr, "vm: initialize attributes\n");
            instructions.rewind();
            call(dab_register_t::nilreg(), "__init", 0, "", nullptr);
            execute(instructions);
        }
        instructions.rewind();
        call(dab_register_t::nilreg(), "main", 0, "", nullptr);
        if (autorun)
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
    return stack[frame_position + 0].data.fixnum;
}

void DabVM::push_constant(const DabValue &value)
{
    constants.push_back(value);
}

void DabVM::call(dab_register_t out_reg, const std::string &name, int n_args,
                 const std::string &block_name, const DabValue &capture, bool use_reglist,
                 std::vector<dab_register_t> reglist)
{
    if (verbose)
    {
        fprintf(stderr, "vm: call <%s> with %d arguments and <%s> block.\n", name.c_str(), n_args,
                block_name.c_str());
    }
    if (!functions.count(name))
    {
        fprintf(stderr, "vm error: Unknown function <%s>.\n", name.c_str());
        exit(1);
    }
    if (block_name != "")
    {
        call_function_block(false, out_reg, nullptr, functions[name], n_args, functions[block_name],
                            capture, use_reglist, reglist);
    }
    else
    {
        call_function(false, out_reg, nullptr, functions[name], n_args, use_reglist, reglist);
    }
}

void DabVM::call_function_block(bool use_self, dab_register_t out_reg, const DabValue &self,
                                const DabFunction &fun, int n_args, const DabFunction &blockfun,
                                const DabValue &capture, bool use_reglist,
                                std::vector<dab_register_t> reglist)
{
    assert(blockfun.regular);

    _call_function(use_self, out_reg, self, fun, n_args, (void *)blockfun.address, capture,
                   use_reglist, reglist);
}

void DabVM::call_function(bool use_self, dab_register_t out_reg, const DabValue &self,
                          const DabFunction &fun, int n_args, bool use_reglist,
                          std::vector<dab_register_t> reglist)
{
    _call_function(use_self, out_reg, self, fun, n_args, nullptr, nullptr, use_reglist, reglist);
}

void DabVM::_call_function(bool use_self, dab_register_t out_reg, const DabValue &self,
                           const DabFunction &fun, int n_args, void *blockaddress,
                           const DabValue &capture, bool use_reglist,
                           std::vector<dab_register_t> reglist)
{
    if (verbose)
    {
        fprintf(stderr, "vm: call <%s> %sand %d arguments -> 0x%x.\n", fun.name.c_str(),
                blockaddress ? "with block " : "", n_args, out_reg.value());
    }

    if (fun.regular)
    {
        push_new_frame(use_self, self, n_args, (uint64_t)blockaddress, out_reg, capture,
                       use_reglist, reglist);
        instructions.seek(fun.address);
    }
    else
    {
        const auto n_ret = 1;
        if (use_reglist)
        {
            for (auto reg : reglist)
            {
                stack.push_value(register_get(reg));
            }
            if (use_self)
            {
                stack.push_value(self);
            }
        }
        fun.extra(n_args, n_ret, blockaddress);
        if (!out_reg.nil())
        {
            register_set(out_reg, stack.pop_value());
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

void DabVM::reflect(size_t reflection_type, const DabValue &symbol)
{
    switch (reflection_type)
    {
    case REFLECT_METHOD_ARGUMENTS:
    case REFLECT_METHOD_ARGUMENT_NAMES:
        reflect_method_arguments(reflection_type, symbol);
        break;
    default:
        fprintf(stderr, "vm: unknown reflection %d\n", (int)reflection_type);
        exit(1);
        break;
    }
}

void DabVM::reflect_method_arguments(size_t reflection_type, const DabValue &symbol)
{
    const auto &function   = functions[symbol.data.string];
    const auto &reflection = function.reflection;

    auto n = reflection.arg_names.size();

    DabValue array_class = classes[CLASS_ARRAY];
    DabValue value       = array_class.create_instance();
    auto &   array       = value.array();
    array.resize(n);
    for (size_t i = 0; i < n; i++)
    {
        DabValue value;
        if (reflection_type == REFLECT_METHOD_ARGUMENT_NAMES)
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
    stack.push_value(value);
}

bool DabVM::execute_single(Stream &input)
{
    auto pos    = input.position();
    auto opcode = input.read_uint8();
    if (verbose)
    {
        fprintf(stderr, "@ %d: %d\n", (int)pos, (int)opcode);
    }
    switch (opcode)
    {
    case OP_DESCRIBE_FUNCTION:
    {
        auto  name       = input.read_vlc_string();
        auto  arg_count  = input.read_uint16();
        auto &reflection = functions[name].reflection;
        reflection.arg_names.resize(arg_count);
        reflection.arg_klasses.resize(arg_count);
        reflection.ret_klass = stack.pop_value().class_index();
        fprintf(stderr, "vm: describe %s:\n", name.c_str());
        fprintf(stderr, "vm:   return: %s\n", classes[reflection.ret_klass].name.c_str());
        for (size_t i = 0; i < arg_count; i++)
        {
            auto klass                    = stack.pop_value().class_index();
            auto name                     = stack.pop_symbol();
            auto arg_i                    = arg_count - i - 1;
            reflection.arg_klasses[arg_i] = klass;
            reflection.arg_names[arg_i]   = name;
            fprintf(stderr, "vm:   arg[%d]: %s '%s'\n", (int)arg_i, classes[klass].name.c_str(),
                    name.c_str());
        }
        break;
    }
    case OP_LOAD_FUNCTION:
    {
        size_t _ip         = ip() - 1;
        size_t address     = input.read_uint16();
        auto   name        = input.read_vlc_string();
        auto   class_index = input.read_uint16();
        add_function(address + _ip, name, class_index);
        break;
    }
    case OP_REFLECT:
    {
        size_t reflection_type = input.read_uint16();
        auto   symbol          = stack.pop_symbol();
        reflect(reflection_type, symbol);
        break;
    }
    case OP_CONSTANT_SYMBOL:
    {
        auto name = input.read_vlc_string();
        push_constant_symbol(name);
        break;
    }
    case OP_CONSTANT_STRING:
    {
        auto name = input.read_vlc_string();
        push_constant_string(name);
        break;
    }
    case OP_CONSTANT_NUMBER:
    {
        auto value = input.read_uint64();
        push_constant_fixnum(value);
        break;
    }
    case OP_PUSH_CONSTANT:
    {
        auto index = input.read_uint16();
        stack.push(constants[index]);
        break;
    }
    case OP_PUSH_METHOD:
    {
        auto name = input.read_vlc_string();
        push_method(name);
        break;
    }
    case OP_Q_SET_CALL:
    {
        auto out_reg = input.read_reg();
        auto symbol  = input.read_symbol();
        auto name    = constants[symbol].data.string;
        auto reglist = input.read_reglist();
        call(out_reg, name, reglist.size(), "", nullptr, true, reglist);
        break;
    }
    case OP_Q_SET_CALL_BLOCK:
    {
        auto out_reg      = input.read_reg();
        auto symbol       = input.read_symbol();
        auto name         = constants[symbol].data.string;
        auto block_symbol = input.read_symbol();
        auto block_name   = constants[block_symbol].data.string;
        auto capture_reg  = input.read_reg();
        auto capture      = register_get(capture_reg);
        auto reglist      = input.read_reglist();

        call(out_reg, name, reglist.size(), block_name, capture, true, reglist);
        break;
    }
    case OP_Q_SET_INSTCALL_BLOCK:
    {
        auto out_reg  = input.read_reg();
        auto self_reg = input.read_reg();
        auto symbol   = input.read_uint16();
        auto name     = constants[symbol].data.string;

        auto block_symbol = input.read_symbol();
        auto block_name   = constants[block_symbol].data.string;
        auto capture_reg  = input.read_reg();
        auto capture      = register_get(capture_reg);

        auto reglist = input.read_reglist();
        auto n_args  = reglist.size();
        auto n_rets  = 1;
        auto recv    = register_get(self_reg);

        instcall(recv, name, n_args, n_rets, block_name, capture, true, out_reg, reglist);
        break;
    }
    case OP_YIELD:
    {
        auto n_args = input.read_uint16();

        auto self = get_self();
        auto addr = get_block_addr();

        if (verbose)
        {
            fprintf(stderr, "vm: yield to %p with %d arguments.\n", (void *)addr, (int)n_args);
            fprintf(stderr, "vm: capture data is ");
            get_block_capture().dump(stderr);
            fprintf(stderr, ".\n");
        }

        push_new_frame(true, self, n_args, 0, dab_register_t::nilreg(), get_block_capture());
        instructions.seek(addr);

        break;
    }
    case OP_PUSH_HAS_BLOCK:
    {
        auto addr = get_block_addr();
        fprintf(stderr, "vm: has block? (%p)\n", (void *)addr);
        stack.push(addr != 0);
        break;
    }
    case OP_PUSH_NIL:
    {
        stack.push_nil();
        break;
    }
    case OP_PUSH_SSA:
    {
        auto reg_index = input.read_reg();
        stack.push(register_get(reg_index));
        break;
    }
    case OP_Q_SET_CLOSURE:
    {
        auto reg_index     = input.read_reg();
        auto closure_index = input.read_uint16();
        auto closure       = get_block_capture();
        assert(closure.data.type == TYPE_ARRAY);
        auto &array = closure.array();
        if (verbose)
        {
            fprintf(stderr, "vm: get captured var %d (of %lu).\n", closure_index, array.size());
        }
        auto value = array[closure_index];
        register_set(reg_index, value);
        break;
    }
    case OP_Q_SET_CONSTANT:
    {
        auto reg_index      = input.read_reg();
        auto constant_index = input.read_int16();
        register_set(reg_index, constants[constant_index]);
        break;
    }
    case OP_Q_SET_POP:
    {
        auto reg_index = input.read_reg();
        auto value     = stack.pop_value();
        register_set(reg_index, value);
        break;
    }
    case OP_Q_SET_TRUE:
    {
        auto reg_index = input.read_reg();
        register_set(reg_index, DabValue(true));
        break;
    }
    case OP_Q_SET_FALSE:
    {
        auto reg_index = input.read_reg();
        register_set(reg_index, DabValue(false));
        break;
    }
    case OP_Q_SET_NUMBER:
    {
        auto reg_index = input.read_reg();
        auto number    = input.read_uint64();
        register_set(reg_index, DabValue(number));
        break;
    }
    case OP_Q_SET_NIL:
    {
        auto reg_index = input.read_reg();
        register_set(reg_index, nullptr);
        break;
    }
    case OP_Q_SET_ARG:
    {
        auto reg_index = input.read_reg();
        auto arg_index = input.read_uint16();
        auto var       = get_arg(arg_index);
        register_set(reg_index, var);
        break;
    }
    case OP_Q_SET_CLASS:
    {
        auto reg_index   = input.read_reg();
        auto klass_index = input.read_uint16();
        auto klass       = classes[klass_index];
        register_set(reg_index, klass);
        break;
    }
    case OP_Q_SET_REG:
    {
        auto dst_index = input.read_reg();
        auto src_index = input.read_reg();
        register_set(dst_index, register_get(src_index));
        break;
    }
    case OP_Q_RETURN:
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
        auto mod = input.read_int16() - 3;
        if (verbose)
        {
            fprintf(stderr, "JMP(%d), new address: %p -> %p\n", mod, (void *)ip(),
                    (void *)(ip() + mod));
        }
        instructions.seek(ip() + mod);
        break;
    }
    case OP_JMP_IF:
    case OP_JMP_IFN:
    {
        auto mod   = input.read_int16() - 3;
        auto value = stack.pop_value();
        if (value.truthy() == (opcode == OP_JMP_IF))
        {
            instructions.seek(ip() + mod);
        }
        break;
    }
    case OP_JMP_IF2:
    {
        auto mod_true  = input.read_int16() - 5;
        auto mod_false = input.read_int16() - 5;
        auto value     = stack.pop_value();
        auto test      = value.truthy();
        instructions.seek(ip() + (test ? mod_true : mod_false));
        break;
    }
    case OP_Q_JMP_IF2:
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
    case OP_PUSH_ARG:
    {
        auto index = input.read_uint16();
        auto var   = get_arg(index);
        stack.push(var);
        break;
    }
    case OP_Q_SET_SYSCALL:
    {
        auto reg     = input.read_reg();
        auto call    = input.read_uint8();
        auto reglist = input.read_reglist();
        kernelcall(true, reg, call, true, reglist, true);
        break;
    }
    case OP_DEFINE_CLASS:
    {
        auto name         = input.read_vlc_string();
        auto index        = input.read_uint16();
        auto parent_index = input.read_uint16();
        add_class(name, index, parent_index);
        break;
    }
    case OP_PUSH_CLASS:
    {
        auto index = input.read_uint16();
        push_class(index);
        break;
    }
    case OP_Q_SET_INSTCALL:
    {
        auto out_reg  = input.read_reg();
        auto self_reg = input.read_reg();
        auto symbol   = input.read_uint16();
        auto name     = constants[symbol].data.string;
        auto reglist  = input.read_reglist();
        auto n_args   = reglist.size();
        auto n_rets   = 1;
        auto recv     = register_get(self_reg);
        if (verbose)
        {
            fprintf(stderr, "vm: instcall, recv = ");
            recv.dump(stderr);
            fprintf(stderr, "\n");
        }
        instcall(recv, name, n_args, n_rets, "", nullptr, true, out_reg, reglist);
        break;
    }
    case OP_PUSH_SELF:
    {
        stack.push(get_self());
        break;
    }
    case OP_PUSH_INSTVAR:
    {
        auto name = stack.pop_symbol();
        get_instvar(name, false, dab_register_t::nilreg());
        break;
    }
    case OP_Q_SET_INSTVAR:
    {
        auto out_reg = input.read_reg();
        auto symbol  = input.read_symbol();
        auto name    = constants[symbol].data.string;
        get_instvar(name, true, out_reg);
        break;
    }
    case OP_Q_CHANGE_INSTVAR:
    {
        auto symbol = input.read_symbol();
        auto reg    = input.read_reg();
        auto name   = constants[symbol].data.string;
        auto value  = register_get(reg);
        set_instvar(name, value);
        break;
    }
    case OP_PUSH_ARRAY:
    {
        auto n = input.read_uint16();
        push_array(n);
        break;
    }
    case OP_PUSH_TRUE:
    {
        stack.push(true);
        break;
    }
    case OP_PUSH_FALSE:
    {
        stack.push(false);
        break;
    }
    case OP_BREAK_LOAD:
    {
        return false;
    }
    case OP_STACK_RESERVE:
    {
        auto n = input.read_uint16();
        assert(n == 0);
        break;
    }
    case OP_COV_FILE:
    {
        auto hash  = input.read_uint16();
        auto fname = input.read_vlc_string();
        coverage.add_file(hash, fname);
        break;
    }
    case OP_COV:
    {
        auto hash = input.read_uint16();
        auto line = input.read_uint16();
        coverage.add_line(hash, line);
        break;
    }
    case OP_POP:
    {
        auto n = input.read_uint16();
        for (size_t i = 0; i < n; i++)
            stack.pop_value();
        break;
    }
    case OP_PUSH_STRING:
    {
        auto s = input.read_vlc_string();
        stack.push(s);
        break;
    }
    case OP_PUSH_NUMBER:
    {
        auto     n             = input.read_uint64();
        DabValue value         = n;
        value.data.is_constant = true;
        stack.push(value);
        break;
    }
    case OP_PUSH_NUMBER_UINT8:
    {
        auto     n = input.read_uint8();
        DabValue value(CLASS_UINT8, n);
        value.data.is_constant = true;
        stack.push(value);
        break;
    }
    case OP_PUSH_NUMBER_INT32:
    {
        auto     n = input.read_int32();
        DabValue value(CLASS_INT32, n);
        value.data.is_constant = true;
        stack.push(value);
        break;
    }
    case OP_PUSH_NUMBER_UINT32:
    {
        auto     n = input.read_uint32();
        DabValue value(CLASS_UINT32, n);
        value.data.is_constant = true;
        stack.push(value);
        break;
    }
    case OP_PUSH_NUMBER_UINT64:
    {
        auto     n = input.read_uint64();
        DabValue value(CLASS_UINT64, n);
        value.data.is_constant = true;
        stack.push(value);
        break;
    }
    case OP_PUSH_SYMBOL:
    {
        auto     s = input.read_vlc_string();
        DabValue ds(s);
        ds.data.type = TYPE_SYMBOL;
        stack.push(ds);
        break;
    }
    case OP_Q_RELEASE:
    {
        auto reg   = input.read_reg();
        auto value = register_get(reg);
        value.release();
        register_set(reg, nullptr);
        break;
    }
    case OP_CAST:
    {
        auto klass_index = input.read_uint16();
        auto value       = stack.pop_value();
        stack.push_value(cast(value, klass_index));
        break;
    }
    default:
        fprintf(stderr, "VM error: Unknown opcode <%02x> (%d).\n", (int)opcode, (int)opcode);
        exit(1);
        break;
    }
    return true;
}

void DabVM::push_array(size_t n)
{
    DabValue array_class = classes[CLASS_ARRAY];
    DabValue value       = array_class.create_instance();
    auto &   array       = value.array();
    array.resize(n);
    for (size_t i = 0; i < n; i++)
    {
        array[n - i - 1] = stack.pop_value();
    }
    stack.push_value(value);
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

void DabVM::push_class(int index)
{
    stack.push(classes[index]);
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
    else if (from_fixnum && to == CLASS_INT32)
    {
        return DabValue(to, (int32_t)value.data.fixnum);
    }
    else if (from == CLASS_UINT32 && to == CLASS_INT32)
    {
        return DabValue(to, (int32_t)value.data.num_uint32);
    }
    else if (from == CLASS_INT32 && to == CLASS_UINT64)
    {
        return DabValue(to, (uint64_t)value.data.num_int32);
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
        copy.data.intptr = (void *)value.data.string.c_str();
        return copy;
    }
    else if (from == CLASS_BYTEBUFFER && to == CLASS_INTPTR)
    {
        DabValue copy;
        copy.data.type   = TYPE_INTPTR;
        copy.data.intptr = &value.bytebuffer()[0];
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

void DabVM::instcall(const DabValue &recv, const std::string &name, size_t n_args, size_t n_rets,
                     const std::string &block_name, const DabValue &capture, bool use_reglist,
                     dab_register_t outreg, std::vector<dab_register_t> reglist)
{
    assert(n_rets == 1);
    auto  class_index = recv.class_index();
    auto &klass       = get_class(class_index);
    stack.push_value(recv);
    auto &fun = klass.get_function(recv, name);

    if (block_name != "")
    {
        call_function_block(true, outreg, recv, fun, 1 + n_args, functions[block_name], capture,
                            use_reglist, reglist);
    }
    else
    {
        call_function(true, outreg, recv, fun, 1 + n_args, use_reglist, reglist);
    }
}

void DabVM::yield(void *block_addr, const std::vector<DabValue> arguments)
{
    auto n_args = arguments.size();

    auto self = get_self();

    if (verbose)
    {
        fprintf(stderr, "vm: vm api yield to %p with %d arguments.\n", (void *)block_addr,
                (int)n_args);
        fprintf(stderr, "vm: capture data is ");
        get_block_capture().dump(stderr);
        fprintf(stderr, ".\n");
    }

    auto stack_pos = stack.size() + 1; // RET 1

    for (auto &arg : arguments)
    {
        stack.push(arg);
    }

    push_new_frame(true, self, n_args, 0, dab_register_t::nilreg(), get_block_capture());
    instructions.seek((size_t)block_addr);

    // temporary hack
    while (stack.size() != stack_pos)
    {
        execute_single(instructions);
    }
}

void DabVM::kernelcall(bool use_out_reg, dab_register_t out_reg, int call, bool use_reglist,
                       std::vector<dab_register_t> reglist, bool output_value)
{
    switch (call)
    {
    case KERNEL_PRINT:
    {
        kernel_print(use_out_reg, out_reg, use_reglist, reglist, output_value);
        break;
    }
    case KERNEL_EXIT:
    {
        DabValue value;
        if (!use_reglist)
        {
            auto value = stack.pop_value();
        }
        else
        {
            assert(reglist.size() == 1);
            value = register_get(reglist[0]);
        }
        exit(value.data.fixnum);
        break;
    }
    case KERNEL_USECOUNT:
    {
        DabValue value;
        if (!use_reglist)
        {
            auto value = stack.pop_value();
        }
        else
        {
            assert(reglist.size() == 1);
            value = register_get(reglist[0]);
        }

        auto dab_value = uint64_t(value.use_count());

        if (!output_value)
            break;

        if (out_reg.nil())
        {
            if (!use_out_reg)
            {
                stack.push_value(dab_value);
            }
        }
        else
        {
            register_set(out_reg, dab_value);
        }
        break;
    }
    default:
        fprintf(stderr, "VM error: Unknown kernel call <%d>.\n", (int)call);
        exit(1);
        break;
    }
}

void DabVM::push_constant_symbol(const std::string &name)
{
    DabValue val;
    val.data.type   = TYPE_SYMBOL;
    val.data.string = name;
    push_constant(val);
}

void DabVM::push_constant_string(const std::string &name)
{
    DabValue val;
    val.data.type        = TYPE_STRING;
    val.data.string      = name;
    val.data.is_constant = true;
    push_constant(val);
}

void DabVM::push_constant_fixnum(uint64_t value)
{
    DabValue val;
    val.data.type        = TYPE_FIXNUM;
    val.data.fixnum      = value;
    val.data.is_constant = true;
    push_constant(val);
}

void DabVM::push_method(const std::string &name)
{
    DabValue val;
    val.data.type   = TYPE_METHOD;
    val.data.string = name;
    stack.push_value(val);
}

void DabVM::add_function(size_t address, const std::string &name, uint16_t class_index)
{
    fprintf(stderr, "vm: add function <%s>.\n", name.c_str());
    DabFunction function;
    function.address = address;
    function.name    = name;
    if (class_index == 0xFFFF)
    {
        functions[name] = function;
    }
    else
    {
        get_class(class_index).functions[name] = function;
    }
}

void DabVM::extract(const std::string &name)
{
    FILE *output = dab_output;

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

struct DabRunOptions
{
    FILE *input           = stdin;
    bool  close_file      = false;
    bool  autorun         = true;
    bool  extract         = false;
    bool  raw             = false;
    bool  cov             = false;
    bool  autorelease     = true;
    bool  verbose         = false;
    bool  with_attributes = false;
    bool  leaktest        = false;

    FILE *output       = stdout;
    bool  close_output = false;

    std::string extract_part;

    void parse(const std::vector<std::string> &args);
};

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

    if (flags["--cov"])
    {
        this->cov = true;
    }

    if (flags["--noautorelease"])
    {
        this->autorelease = false;
    }
}

int unsafe_main(int argc, char **argv)
{
    setup_handlers();

    DabRunOptions            options;
    std::vector<std::string> args;
    for (int i = 1; i < argc; i++)
    {
        args.push_back(argv[i]);
    }
    options.parse(args);
    fprintf(stderr, "VM options: autorun %s raw %s cov %s\n", options.autorun ? "yes" : "no",
            options.raw ? "yes" : "no", options.cov ? "yes" : "no");

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
    DabVM vm;
    vm.dab_output      = options.output;
    vm.verbose         = options.verbose;
    vm.autorelease     = options.autorelease;
    vm.with_attributes = options.with_attributes;
    auto ret_value     = vm.run(input, options.autorun, options.raw, options.cov);
    vm.constants.resize(0);
    vm._registers.resize(0);
    vm._register_stack.resize(0);
    if (options.extract)
    {
        vm.extract(options.extract_part);
    }
    if (options.close_file)
    {
        fclose(stream);
    }
    if (options.close_output)
    {
        fclose(options.output);
    }
    if (options.cov)
    {
        vm.coverage.dump(stdout);
    }
    if (ret_value == 0 && options.leaktest)
    {
        if (vm.run_leaktest(stdout))
        {
            ret_value = 1;
        }
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
