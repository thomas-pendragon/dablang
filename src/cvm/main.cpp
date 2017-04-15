#include "cvm.h"

#include "../cshared/opcodes.h"

enum
{
    KERNEL_PRINT = 0x00,
    KERNEL_EXIT  = 0x01,
};

DabVM::DabVM()
{
    define_defaults();
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
    arg.print(*this, stderr);
    fprintf(stderr, " ]\n");
    if (!coverage_testing)
    {
        arg.print(*this, stdout);
    }
    stack.push_nil();
}

bool DabVM::pop_frame(bool regular)
{
    int    frame_loc = frame_position;
    int    n_args    = number_of_args();
    size_t prev_pos  = prev_frame_position();
    auto   retval    = get_retval();
    auto   prev_ip   = get_prev_ip();

    if (prev_pos == (size_t)-1)
    {
        return false;
    }

    stack.resize(frame_loc - 2 - n_args);

    frame_position = prev_pos;

    if (regular)
    {
        stack.push(retval);
        fprintf(stderr, "VM: seek ret to %p (%d).\n", (void *)prev_ip, (int)prev_ip);
        instructions.seek(prev_ip);
    }

    return true;
}

size_t DabVM::stack_position() const
{
    return stack.size();
}

void DabVM::push_new_frame(const DabValue &self, int n_args)
{
    stack.push((uint64_t)ip());
    stack.push((uint64_t)frame_position); // push previous frame
    frame_position = stack_position();
    stack.push((uint64_t)n_args); // number of arguments
    stack.push(self);
    {
        // push retvalue
        DabValue val;
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
        instructions.rewind();
        call("main", 0);
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

DabValue &DabVM::get_var(int var_index)
{
    auto index = frame_position + 3 + var_index;
    return stack[index];
}

DabValue &DabVM::get_arg(int arg_index)
{
    auto index = frame_position - number_of_args() - 2 + arg_index;
    return stack[index];
}

DabValue &DabVM::get_retval()
{
    auto index = frame_position + 2;
    return stack[index];
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
        push_new_frame(self, n_args);
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
        if (!execute_single(input))
        {
            break;
        }
    }
}

bool DabVM::execute_single(Stream &input)
{
    auto opcode = input.read_uint8();
    switch (opcode)
    {
    case OP_LOAD_FUNCTION:
    {
        size_t _ip         = ip() - 1;
        size_t address     = input.read_uint16();
        auto   name        = input.read_vlc_string();
        auto   class_index = input.read_uint16();
        add_function(address + _ip, name, class_index);
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
    case OP_CALL:
    {
        auto name   = stack.pop_symbol();
        auto n_args = input.read_uint16();
        auto n_rets = input.read_uint16();
        assert(n_rets == 1);
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
        auto nrets = input.read_uint16();
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
    case OP_KERNELCALL:
    {
        auto call = input.read_uint8();
        kernelcall(call);
        break;
    }
    case OP_DEFINE_CLASS:
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
        auto name   = stack.pop_symbol();
        auto recv   = stack.pop_value();
        auto n_args = input.read_uint16();
        auto n_rets = input.read_uint16();
        instcall(recv, name, n_args, n_rets);
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
    if (!classes.count(index))
    {
        DabClass klass;
        klass.name     = name;
        klass.index    = index;
        klass.builtin  = false;
        classes[index] = klass;
    }
}

void DabVM::instcall(const DabValue &recv, const std::string &name, size_t n_args, size_t n_rets)
{
    assert(n_rets == 1);
    auto  class_index = recv.class_index();
    auto &klass       = get_class(class_index);
    stack.push_value(recv);
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
    case KERNEL_EXIT:
    {
        auto value = stack.pop_value();
        exit(value.data.fixnum);
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

void DabVM::add_function(size_t address, const std::string &name, uint16_t class_index)
{
    fprintf(stderr, "VM: add function <%s>.\n", name.c_str());
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
    if (name == "rip")
    {
        printf("%zu", ip());
    }
    else if (name == "stack[-1]")
    {
        if (stack.size() == 0)
        {
            fprintf(stderr, "VM: empty stack.\n");
            exit(1);
        }
        stack[stack.size() - 1].dump(*this, stdout);
    }
    else
    {
        fprintf(stderr, "VM: unknown extract option <%s>.\n", name.c_str());
        exit(1);
    }
}

struct DabRunOptions
{
    FILE *      input      = stdin;
    bool        close_file = false;
    bool        autorun    = true;
    bool        extract    = false;
    bool        raw        = false;
    bool        cov        = false;
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
        fprintf(stderr, "VM: too many file arguments.\n");
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

    if (flags["--raw"])
    {
        this->raw = true;
    }

    if (flags["--cov"])
    {
        this->cov = true;
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
    auto  ret_value = vm.run(input, options.autorun, options.raw, options.cov);
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
