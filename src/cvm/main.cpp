#include "cvm.h"

#include "opcodes.h"

enum
{
    KERNEL_PRINT = 0x00,
};

DabVM::DabVM()
{
    define_defaults();
}

void DabVM::kernel_print()
{
    auto arg = stack.pop_value();
    fprintf(stderr, "[ ");
    arg.print(*this, stderr);
    fprintf(stderr, " ]\n");
    arg.print(*this, stdout);
    stack.push_nil();
}

void DabVM::pop_frame(bool regular)
{
    int    frame_loc = frame_position;
    int    n_args    = number_of_args();
    size_t prev_pos  = prev_frame_position();
    auto   retval    = get_retval();
    auto   prev_ip   = get_prev_ip();

    if (prev_pos == -1)
    {
        exit(0);
    }

    stack.resize(frame_loc - 2 - n_args);

    frame_position = prev_pos;

    if (regular)
    {
        push(retval);
        fprintf(stderr, "VM: seek ret to %p (%d).\n", (void *)prev_ip, (int)prev_ip);
        instructions.seek(prev_ip);
    }
}

void DabVM::push(int kind, int value)
{
    DabValue val;
    val.data.kind   = kind;
    val.data.type   = TYPE_FIXNUM;
    val.data.fixnum = value;
    stack.push_value(val);
}

void DabVM::push(int kind, uint64_t value)
{
    DabValue val;
    val.data.kind   = kind;
    val.data.type   = TYPE_FIXNUM;
    val.data.fixnum = value;
    stack.push_value(val);
}

void DabVM::push(int kind, bool value)
{
    DabValue val;
    val.data.kind    = kind;
    val.data.type    = TYPE_BOOLEAN;
    val.data.boolean = value;
    stack.push_value(val);
}

void DabVM::stack_push(const std::string &value)
{
    push(VAL_STACK, value);
}

void DabVM::stack_push(uint64_t value)
{
    push(VAL_STACK, value);
}

void DabVM::stack_push(bool value)
{
    push(VAL_STACK, value);
}

void DabVM::push(int kind, const std::string &value)
{
    DabValue val;
    val.data.kind   = kind;
    val.data.type   = TYPE_STRING;
    val.data.string = value;
    stack.push_value(val);
}

void DabVM::push(DabValue val)
{
    val.data.kind = VAL_STACK;
    stack.push_value(val);
}

size_t DabVM::stack_position() const
{
    return stack.size();
}

void DabVM::push_new_frame(const DabValue &self, int n_args, int n_locals)
{
    push(VAL_FRAME_PREV_IP, (uint64_t)ip());
    push(VAL_FRAME_PREV_STACK, (uint64_t)frame_position); // push previous frame
    frame_position = stack_position();
    push(VAL_FRAME_COUNT_ARGS, n_args);   // number of arguments
    push(VAL_FRAME_COUNT_VARS, n_locals); // number of locals
    stack.push(self, VAL_SELF);
    {
        // push retvalue
        DabValue val;
        val.data.kind = VAL_RETVAL;
        val.data.type = TYPE_INVALID;
        stack.push_value(val);
    }
    for (int i = 0; i < n_locals; i++)
    {
        DabValue val;
        val.data.kind = VAL_VARIABLE;
        val.data.type = TYPE_INVALID;
        stack.push_value(val);
    }
}

void DabVM::_dump(const char *name, const std::vector<DabValue> &data)
{
    fprintf(stderr, "Dump of %s:\n", name);
    for (size_t i = 0; i < data.size(); i++)
    {
        fprintf(stderr, "[%4zu] ", i);
        data[i].dump(*this);
        fprintf(stderr, "\n");
    }
}

size_t DabVM::ip() const
{
    return instructions.position();
}

void DabVM::dump()
{
    fprintf(stderr, "IP = %p (%d) Frame = %d\n", (void *)ip(), (int)ip(), (int)frame_position);
    fprintf(stderr, "Classes:\n");
    for (const auto &it : classes)
    {
        fprintf(stderr, " - 0x%04x %s (super = 0x%04x)\n", it.first, it.second.name.c_str(),
                it.second.superclass_index);
        for (const auto &fin : it.second.static_functions)
        {
            fprintf(stderr, "   ::%s\n", fin.first.c_str());
        }
        for (const auto &fin : it.second.functions)
        {
            fprintf(stderr, "    .%s\n", fin.first.c_str());
        }
    }
    fprintf(stderr, "Dump of functions:\n");
    for (auto it : functions)
    {
        auto &fun = it.second;
        fprintf(stderr, " - %s: %s at %p\n", fun.name.c_str(), fun.regular ? "regular" : "extra",
                (void *)fun.address);
    }
    _dump("constants", constants);
    _dump("stack", stack._data);
}

int DabVM::run(Stream &input)
{
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

    execute(input);

    call("main", 0);
    execute(instructions);

    return 0;
}

DabValue &DabVM::get_var(int var_index)
{
    auto index = frame_position + 4 + var_index;
    return stack[index];
}

DabValue &DabVM::start_of_constants()
{
    return stack[frame_position];
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

DabValue &DabVM::get_self()
{
    auto index = frame_position + 2;
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

int DabVM::number_of_vars()
{
    return stack[frame_position + 1].data.fixnum;
}

void DabVM::push_constant(const DabValue &value)
{
    constants.push_back(value);
}

void DabVM::call(const std::string &name, int n_args)
{
    fprintf(stderr, "VM: call <%s> with %d arguments.\n", name.c_str(), n_args);
    if (!functions.count(name))
    {
        fprintf(stderr, "VM error: Unknown function <%s>.\n", name.c_str());
        exit(1);
    }
    call_function(nullptr, functions[name], n_args);
}

void DabVM::call_function(const DabValue &self, const DabFunction &fun, int n_args)
{
    if (fun.regular)
    {
        push_new_frame(self, n_args, fun.n_locals);
        fprintf(stderr, "VM: %s has %d local vars.\n", fun.name.c_str(), fun.n_locals);
        instructions.seek(fun.address);
    }
    else
    {
        const auto n_ret = 1;
        fun.extra(n_args, n_ret);
    }
}

void DabVM::execute(Stream &input)
{
    while (!input.eof())
    {
        execute_single(input);
    }
}

void DabVM::execute_single(Stream &input)
{
    fprintf(stderr, "\n");
    // dump();
    auto opcode = input.read_uint8();
    fprintf(stderr, "Opcode: %d\n", (int)opcode);
    switch (opcode)
    {
    case OP_START_FUNCTION:
    {
        auto name        = input.read_vlc_string();
        auto class_index = input.read_uint16();
        auto n_locals    = input.read_uint16();
        auto body_length = input.read_uint16();
        add_function(input, name, class_index, n_locals, body_length);
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
    case OP_CONSTANT_BOOLEAN:
    {
        auto value = input.read_uint16();
        push_constant_boolean(value);
        break;
    }
    case OP_PUSH_CONSTANT:
    {
        auto index = input.read_uint16();
        push(constants[index]);
        break;
    }
    case OP_CALL:
    {
        auto name   = stack_pop_symbol();
        auto n_args = input.read_uint16();
        auto n_rets = input.read_uint16();
        call(name, n_args);
        break;
    }
    case OP_PUSH_NIL:
    {
        stack.push_nil();
        break;
    }
    case OP_RETURN:
    {
        auto  nrets      = input.read_uint16();
        auto &retval     = get_retval();
        retval           = stack.pop_value();
        retval.data.kind = VAL_RETVAL;
        pop_frame(true);
        break;
    }
    case OP_JMP:
    {
        auto mod = input.read_uint16() - 3;
        fprintf(stderr, "JMP(%d), new address: %p -> %p\n", mod, (void *)ip(),
                (void *)(ip() + mod));
        instructions.seek(ip() + mod);
        break;
    }
    case OP_JMP_IFN:
    {
        auto mod   = input.read_uint16() - 3;
        auto value = stack.pop_value();
        if (!value.truthy())
        {
            instructions.seek(ip() + mod);
        }
        break;
    }
    case OP_NOP:
    {
        break;
    }
    case OP_SET_VAR:
    {
        auto  index   = input.read_uint16();
        auto  value   = stack.pop_value();
        auto &var     = get_var(index);
        var           = value;
        var.data.kind = VAL_VARIABLE;
        break;
    }
    case OP_PUSH_VAR:
    {
        auto index = input.read_uint16();
        auto var   = get_var(index);
        push(var);
        break;
    }
    case OP_PUSH_ARG:
    {
        auto index = input.read_uint16();
        auto var   = get_arg(index);
        push(var);
        break;
    }
    case OP_KERNELCALL:
    {
        auto call = input.read_uint8();
        kernelcall(call);
        break;
    }
    case OP_START_CLASS:
    {
        auto name  = input.read_vlc_string();
        auto index = input.read_uint16();
        add_class(name, index);
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
        auto name   = stack_pop_symbol();
        auto recv   = stack.pop_value();
        auto n_args = input.read_uint16();
        auto n_rets = input.read_uint16();
        instcall(recv, name, n_args, n_rets);
        break;
    }
    case OP_PUSH_SELF:
    {
        push(get_self());
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
        assert(n == 0);
        DabValue value;
        value.data.type = TYPE_ARRAY;
        stack.push_value(value);
        break;
    }
    default:
        fprintf(stderr, "VM error: Unknown opcode <%02x> (%d).\n", (int)opcode, (int)opcode);
        exit(1);
        break;
    }
}

void DabVM::get_instvar(const std::string &name)
{
    stack.push_value(get_self().get_instvar(*this, name));
}

void DabVM::set_instvar(const std::string &name, const DabValue &value)
{
    get_self().set_instvar(*this, name, value);
}

void DabVM::push_class(int index)
{
    stack.push(classes[index]);
}

void DabVM::add_class(const std::string &name, int index)
{
    DabClass klass;
    klass.name     = name;
    klass.index    = index;
    klass.builtin  = false;
    classes[index] = klass;
}

void DabVM::instcall(const DabValue &recv, const std::string &name, size_t n_args, size_t n_rets)
{
    auto  class_index = recv.class_index();
    auto &klass       = get_class(class_index);
    stack.push(recv);
    auto &fun = klass.get_function(*this, recv, name);
    call_function(recv, fun, 1 + n_args);
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
    default:
        fprintf(stderr, "VM error: Unknown kernel call <%d>.\n", (int)call);
        exit(1);
        break;
    }
}

std::string DabVM::stack_pop_symbol()
{
    auto val = stack.pop_value();
    if (val.data.type != TYPE_SYMBOL)
    {
        fprintf(stderr, "VM error: value is not a symbol.\n");
        exit(1);
    }
    return val.data.string;
}

void DabVM::push_constant_symbol(const std::string &name)
{
    DabValue val;
    val.data.kind   = VAL_CONSTANT;
    val.data.type   = TYPE_SYMBOL;
    val.data.string = name;
    push_constant(val);
}

void DabVM::push_constant_string(const std::string &name)
{
    DabValue val;
    val.data.kind        = VAL_CONSTANT;
    val.data.type        = TYPE_STRING;
    val.data.string      = name;
    val.data.is_constant = true;
    push_constant(val);
}

void DabVM::push_constant_fixnum(uint64_t value)
{
    DabValue val;
    val.data.kind        = VAL_CONSTANT;
    val.data.type        = TYPE_FIXNUM;
    val.data.fixnum      = value;
    val.data.is_constant = true;
    push_constant(val);
}

void DabVM::push_constant_boolean(bool value)
{
    DabValue val;
    val.data.kind    = VAL_CONSTANT;
    val.data.type    = TYPE_BOOLEAN;
    val.data.boolean = value;
    push_constant(val);
}

void DabVM::add_function(Stream &input, const std::string &name, uint16_t class_index,
                         size_t n_locals, size_t body_length)
{
    auto position = instructions.length();
    fprintf(stderr, "VM: read function <%s>.\n", name.c_str());
    DabFunction function;
    function.address  = position;
    function.n_locals = n_locals;
    function.name     = name;
    if (class_index == 0xFFFF)
    {
        functions[name] = function;
    }
    else
    {
        get_class(class_index).functions[name] = function;
    }
    instructions.append(input, body_length);
}

struct DabRunOptions
{
    FILE *input      = stdin;
    bool  close_file = false;
    bool  autorun    = true;

    void parse(const std::vector<std::string> &args);
};

void DabRunOptions::parse(const std::vector<std::string> &args)
{
    std::map<std::string, bool> flags;
    std::vector<std::string> others;

    for (auto &arg : args)
    {
        if (arg.substr(0, 2) == "--")
        {
            flags[arg] = true;
        }
        else
        {
            others.push_back(arg);
        }
    }

    if (others.size() > 1)
    {
        fprintf(stderr, "VM: too many file arguments.\n");
        exit(1);
    }

    if (others.size() == 1)
    {
        auto filename = others[0].c_str();
        auto file     = fopen(filename, "rb");
        if (!file)
        {
            fprintf(stderr, "VM: cannot open file <%s> for reading!\n", filename);
            exit(1);
        }
        this->input      = file;
        this->close_file = true;
    }

    if (flags["--debug"])
    {
        this->autorun = false;
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

    Stream input;
    byte   buffer[1024];
    auto   stream = options.input;
    while (!feof(stream))
    {
        size_t bytes = fread(buffer, 1, 1024, stream);
        input.append(buffer, bytes);
    }
    DabVM vm;
    auto  ret_value = vm.run(input);
    if (options.close_file)
    {
        fclose(stream);
    }
    return ret_value;
}
