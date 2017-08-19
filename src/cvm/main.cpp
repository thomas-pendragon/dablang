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

void DabVM::kernel_print()
{
    auto stack_pos = stack.size();
    auto arg       = stack.pop_value();
    instcall(arg, "to_s", 0, 1);
    // temporary hack
    while (stack.size() != stack_pos)
    {
        execute_single(instructions);
    }
    arg = stack.pop_value();

    fprintf(stderr, "[ ");
    arg.print(stderr);
    fprintf(stderr, " ]\n");
    if (!coverage_testing)
    {
        arg.print(stdout);
    }
    stack.push_nil();
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

    if (regular)
    {
        if (verbose)
        {
            fprintf(stderr, "vm: release %d local vars\n", (int)get_varcount());
        }
        for (size_t i = 0; i < get_varcount(); i++)
        {
            get_var(i).release();
        }
    }

    stack.resize(frame_loc - 2 - n_args);

    frame_position = prev_pos;

    if (regular)
    {
        if (prev_pos != (size_t)-1)
        {
            stack.push(retval);
        }
        if (verbose)
        {
            fprintf(stderr, "vm: seek ret to %p (%d).\n", (void *)prev_ip, (int)prev_ip);
        }
        instructions.seek(prev_ip);
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

void DabVM::push_new_frame(const DabValue &self, int n_args, uint64_t block_addr)
{
    stack.push((uint64_t)ip());
    stack.push((uint64_t)frame_position); // push previous frame
    frame_position = stack_position();
    stack.push((uint64_t)n_args); // number of arguments
    stack.push(self);
    stack.push(block_addr);
    {
        // push retvalue
        DabValue val;
        val.data.type = TYPE_INVALID;
        stack.push_value(val);
    }
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
            call("__init", 0, "");
            execute(instructions);
        }
        instructions.rewind();
        call("main", 0, "");
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

size_t DabVM::get_varcount()
{
    auto index = frame_position + 4;
    return stack[index].data.fixnum;
}

DabValue &DabVM::get_var(int var_index)
{
    auto index = frame_position + 5 + var_index;
    return stack[index];
}

DabValue &DabVM::get_arg(int arg_index)
{
    auto index = frame_position - number_of_args() - 2 + arg_index;
    return stack[index];
}

DabValue &DabVM::get_retval()
{
    auto index = frame_position + 3;
    return stack[index];
}

uint64_t DabVM::get_block_addr()
{
    auto index = frame_position + 2;
    return stack[index].data.fixnum;
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

void DabVM::call(const std::string &name, int n_args, const std::string &block_name)
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
        call_function_block(nullptr, functions[name], n_args, functions[block_name]);
    }
    else
    {
        call_function(nullptr, functions[name], n_args);
    }
}

void DabVM::call_function_block(const DabValue &self, const DabFunction &fun, int n_args,
                                const DabFunction &blockfun)
{
    assert(blockfun.regular);

    fprintf(stderr, "vm: call <%s> with block and %d arguments.\n", fun.name.c_str(), n_args);

    if (fun.regular)
    {
        push_new_frame(self, n_args, blockfun.address);
        instructions.seek(fun.address);
    }
    else
    {
        const auto n_ret = 1;
        fun.extra(n_args, n_ret, (void *)blockfun.address);
    }
}

void DabVM::call_function(const DabValue &self, const DabFunction &fun, int n_args)
{
    if (fun.regular)
    {
        push_new_frame(self, n_args, 0);
        instructions.seek(fun.address);
    }
    else
    {
        const auto n_ret = 1;
        fun.extra(n_args, n_ret, nullptr);
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

void DabVM::set_ssa(size_t ssa_index, const DabValue &value)
{
    if (ssa_registers.size() <= ssa_index)
    {
        ssa_registers.resize(ssa_index + 1);
    }
    ssa_registers[ssa_index] = value;
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
    case OP_SETV_CONSTANT:
    {
        auto  n_var = input.read_uint16();
        auto  index = input.read_uint16();
        auto &var   = get_var(n_var);
        var         = constants[index];
        break;
    }
    case OP_SETV_CALL:
    {
        auto n_var  = input.read_uint16();
        auto index  = input.read_uint16();
        auto n_args = input.read_uint16();
        auto name   = get_symbol(index);
        call(name, n_args, "");
        auto  value = stack.pop_value();
        auto &var   = get_var(n_var);
        var         = value;
        break;
    }
    case OP_HARDCALL:
    case OP_CALL:
    {
        auto name   = stack.pop_symbol();
        auto n_args = input.read_uint16();
        call(name, n_args, "");
        break;
    }
    case OP_HARDCALL_BLOCK:
    case OP_CALL_BLOCK:
    {
        auto block_name = stack.pop_symbol();
        auto name       = stack.pop_symbol();
        auto n_args     = input.read_uint16();
        auto n_rets     = 1;
        assert(n_rets == 1);
        call(name, n_args, block_name);
        break;
    }
    case OP_YIELD:
    {
        auto n_args = input.read_uint16();

        auto self = get_self();
        auto addr = get_block_addr();

        fprintf(stderr, "vm: yield to %p with %d arguments.\n", (void *)addr, (int)n_args);

        push_new_frame(self, n_args, 0);
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
        auto index = input.read_int16();
        stack.push(ssa_registers[index]);
        break;
    }
    case OP_Q_SET_CONSTANT:
    {
        auto ssa_index      = input.read_int16();
        auto constant_index = input.read_int16();
        set_ssa(ssa_index, constants[constant_index]);
        break;
    }
    case OP_Q_SET_POP:
    {
        auto ssa_index = input.read_int16();
        auto value     = stack.pop_value();
        set_ssa(ssa_index, value);
        break;
    }
    case OP_RETURN:
    {
        auto nrets = 1;
        assert(nrets == 1);
        auto &retval = get_retval();
        retval       = stack.pop_value();
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
    case OP_NOP:
    {
        break;
    }
    case OP_SET_VAR:
    {
        auto  index = input.read_uint16();
        auto  value = stack.pop_value();
        auto &var   = get_var(index);
        var         = value;
        break;
    }
    case OP_PUSH_VAR:
    {
        auto index = input.read_uint16();
        auto var   = get_var(index);
        stack.push(var);
        break;
    }
    case OP_PUSH_ARG:
    {
        auto index = input.read_uint16();
        auto var   = get_arg(index);
        stack.push(var);
        break;
    }
    case OP_SETV_ARG:
    {
        auto  n_var = input.read_uint16();
        auto  index = input.read_uint16();
        auto &var   = get_var(n_var);
        var         = get_arg(index);
        break;
    }
    case OP_SYSCALL:
    {
        auto call = input.read_uint8();
        kernelcall(call);
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
    case OP_INSTCALL:
    {
        auto name   = stack.pop_symbol();
        auto recv   = stack.pop_value();
        auto n_args = input.read_uint16();
        auto n_rets = 1;
        instcall(recv, name, n_args, n_rets);
        break;
    }
    case OP_INSTCALL_BLOCK:
    {
        auto block_name = stack.pop_symbol();
        auto name       = stack.pop_symbol();
        auto recv       = stack.pop_value();
        auto n_args     = input.read_uint16();
        auto n_rets     = 1;
        instcall(recv, name, n_args, n_rets, block_name);
        break;
    }
    case OP_PUSH_SELF:
    {
        stack.push(get_self());
        break;
    }
    case OP_PUSH_INSTVAR:
    {
        auto name = input.read_vlc_string();
        get_instvar(name);
        break;
    }
    case OP_SET_INSTVAR:
    {
        auto name  = input.read_vlc_string();
        auto value = stack.pop_value();
        set_instvar(name, value);
        break;
    }
    case OP_PUSH_ARRAY:
    {
        auto n = input.read_uint16();
        push_array(n);
        break;
    }
    case OP_SETV_NEW_ARRAY:
    {
        auto n_var  = input.read_uint16();
        auto n_args = input.read_uint16();
        push_array(n_args);
        auto  value = stack.pop_value();
        auto &var   = get_var(n_var);
        var         = value;
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
        stack.push((uint64_t)n);
        for (auto i = 0; i < n; i++)
        {
            stack.push(nullptr);
        }
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
    case OP_DUP:
    {
        stack.push_value(stack[-1]);
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
        auto n = input.read_uint64();
        stack.push(n);
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
    case OP_RELEASE_VAR:
    {
        auto index = input.read_uint16();
        get_var(index).release();
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

void DabVM::get_instvar(const std::string &name)
{
    stack.push_value(get_self().get_instvar(name));
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

    auto from_fixnum = from == CLASS_LITERALFIXNUM || from == CLASS_FIXNUM;
    auto to_fixnum   = to == CLASS_LITERALFIXNUM || to == CLASS_FIXNUM;

    if (from_fixnum && to == CLASS_UINT8)
    {
        return DabValue(to, (uint8_t)value.data.fixnum);
    }
    else if (from == CLASS_LITERALFIXNUM && to == CLASS_FIXNUM)
    {
        DabValue copy;
        copy.data.type   = TYPE_FIXNUM;
        copy.data.fixnum = value.data.fixnum;
        return copy;
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
    else if (from == CLASS_NILCLASS && to == CLASS_INTPTR)
    {
        DabValue copy;
        copy.data.type   = TYPE_INTPTR;
        copy.data.intptr = nullptr;
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
        fprintf(stderr, "vm: cannot cast %d to %d.\n", (int)value.class_index(), (int)klass_index);
        exit(1);
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
                     const std::string &block_name)
{
    assert(n_rets == 1);
    auto  class_index = recv.class_index();
    auto &klass       = get_class(class_index);
    stack.push_value(recv);
    auto &fun = klass.get_function(recv, name);

    if (block_name != "")
    {
        call_function_block(recv, fun, 1 + n_args, functions[block_name]);
    }
    else
    {
        call_function(recv, fun, 1 + n_args);
    }
}

void DabVM::kernelcall(int call)
{
    switch (call)
    {
    case KERNEL_PRINT:
    {
        kernel_print();
        break;
    }
    case KERNEL_EXIT:
    {
        auto value = stack.pop_value();
        exit(value.data.fixnum);
        break;
    }
    case KERNEL_USECOUNT:
    {
        auto value = stack.pop_value();
        stack.push_value(uint64_t(value.use_count()));
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
    FILE *output = stdout;

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
    }
    else
    {
        fprintf(stderr, "vm: unknown extract option <%s>.\n", name.c_str());
        exit(1);
    }
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

    if (options.count("--output"))
    {
        this->extract      = true;
        this->extract_part = options["--output"];
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

int main(int argc, char **argv)
{
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
        input.append(buffer, bytes);
    }
    DabVM vm;
    vm.verbose         = options.verbose;
    vm.autorelease     = options.autorelease;
    vm.with_attributes = options.with_attributes;
    auto ret_value     = vm.run(input, options.autorun, options.raw, options.cov);
    vm.constants.resize(0);
    vm.ssa_registers.resize(0);
    if (options.extract)
    {
        vm.extract(options.extract_part);
    }
    if (options.close_file)
    {
        fclose(stream);
    }
    if (options.cov)
    {
        vm.coverage.dump(stdout);
    }
    return ret_value;
}

void DabVM::yield(void *block_addr, const std::vector<DabValue> arguments)
{
    auto n_args = arguments.size();

    auto self = get_self();

    fprintf(stderr, "vm: vm yield to %p with %d arguments.\n", (void *)block_addr, (int)n_args);

    auto stack_pos = stack.size() + 1; // RET 1

    for (auto &arg : arguments)
    {
        stack.push(arg);
    }

    push_new_frame(self, n_args, 0);
    instructions.seek((size_t)block_addr);

    // temporary hack
    while (stack.size() != stack_pos)
    {
        execute_single(instructions);
    }
}
