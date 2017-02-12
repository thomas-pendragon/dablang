#include "cvm.h"

enum
{
    OP_START_FUNCTION   = 0x00,
    OP_CONSTANT_SYMBOL  = 0x01,
    OP_CONSTANT_STRING  = 0x02,
    OP_PUSH_CONSTANT    = 0x03,
    OP_CALL             = 0x04,
    OP_SETVAR           = 0x05,
    OP_PUSH_VAR         = 0x06,
    OP_PUSH_ARG         = 0x07,
    OP_CONSTANT_NUMBER  = 0x08,
    OP_RETURN           = 0x09,
    OP_JMP              = 0x0A,
    OP_JMP_IFN          = 0x0B,
    OP_NOP              = 0x0C,
    OP_CONSTANT_BOOLEAN = 0x0D,
    OP_PUSH_NIL         = 0x0E,
    OP_KERNELCALL       = 0x0F,
    OP_PROPGET          = 0x10,
};

enum
{
    KERNEL_PRINT = 0x00,
};

#define STR2(s) #s
#define STR(s) STR2(s)
#define DAB_DEFINE_OP_STR(op)                                                                      \
    {                                                                                              \
        DabFunction fun;                                                                           \
        fun.name    = STR(op);                                                                     \
        fun.regular = false;                                                                       \
        fun.extra   = [this]() {                                                                   \
            dump();                                                                                \
            auto     arg1 = stack_pop();                                                           \
            auto     arg0 = stack_pop();                                                           \
            uint64_t num  = arg0.fixnum op arg1.fixnum;                                            \
            auto str      = arg0.string op arg1.string;                                            \
            if (arg0.type == TYPE_FIXNUM)                                                          \
                stack_push(num);                                                                   \
            else                                                                                   \
                stack_push(str);                                                                   \
        };                                                                                         \
        functions[STR(op)] = fun;                                                                  \
    }

#define DAB_DEFINE_OP(op)                                                                          \
    {                                                                                              \
        DabFunction fun;                                                                           \
        fun.name    = STR(op);                                                                     \
        fun.regular = false;                                                                       \
        fun.extra   = [this]() {                                                                   \
            dump();                                                                                \
            auto     arg1 = stack_pop();                                                           \
            auto     arg0 = stack_pop();                                                           \
            uint64_t num  = arg0.fixnum op arg1.fixnum;                                            \
            stack_push(num);                                                                       \
        };                                                                                         \
        functions[STR(op)] = fun;                                                                  \
    }

#define DAB_DEFINE_OP_BOOL(op)                                                                     \
    {                                                                                              \
        DabFunction fun;                                                                           \
        fun.name    = STR(op);                                                                     \
        fun.regular = false;                                                                       \
        fun.extra   = [this]() {                                                                   \
            dump();                                                                                \
            auto arg1 = stack_pop();                                                               \
            auto arg0 = stack_pop();                                                               \
            bool test = arg0.fixnum op arg1.fixnum;                                                \
            stack_push(test);                                                                      \
        };                                                                                         \
        functions[STR(op)] = fun;                                                                  \
    }

struct DabVM
{
    Stream instructions;
    std::map<std::string, DabFunction> functions;
    size_t                frame_position = -1;
    Stack                 stack;
    std::vector<DabValue> constants;

    DabVM()
    {
        DAB_DEFINE_OP_STR(+);
        DAB_DEFINE_OP(-);
        DAB_DEFINE_OP(*);
        DAB_DEFINE_OP(/);
        DAB_DEFINE_OP(%);
        DAB_DEFINE_OP_BOOL(==);

        add_c_function("String::upcase", [this]() {
            auto arg0 = stack_pop();
            assert(arg0.type == TYPE_STRING);
            auto &s = arg0.string;
            std::transform(s.begin(), s.end(), s.begin(), ::toupper);
            stack.push(arg0);
        });

        add_c_function("String::class", [this]() {
            stack_pop();
            stack_push(std::string("LiteralString"));
        });
    }

    void add_c_function(const std::string &name, std::function<void()> func)
    {
        DabFunction fun;
        fun.name        = name;
        fun.regular     = false;
        fun.extra       = func;
        functions[name] = fun;
    }

    void kernel_print()
    {
        auto arg = stack_pop();
        fprintf(stderr, "[ ");
        arg.print(stderr);
        fprintf(stderr, " ]\n");
        arg.print(stdout);
        stack_push_nil();
    }

    void pop_frame(bool regular)
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

    void push(int kind, int value)
    {
        DabValue val;
        val.kind   = kind;
        val.type   = TYPE_FIXNUM;
        val.fixnum = value;
        stack.push_value(val);
    }

    void push(int kind, uint64_t value)
    {
        DabValue val;
        val.kind   = kind;
        val.type   = TYPE_FIXNUM;
        val.fixnum = value;
        stack.push_value(val);
    }

    void push(int kind, bool value)
    {
        DabValue val;
        val.kind    = kind;
        val.type    = TYPE_BOOLEAN;
        val.boolean = value;
        stack.push_value(val);
    }

    void stack_push(const std::string &value)
    {
        push(VAL_STACK, value);
    }

    void stack_push(uint64_t value)
    {
        push(VAL_STACK, value);
    }

    void stack_push(bool value)
    {
        push(VAL_STACK, value);
    }

    void push(int kind, const std::string &value)
    {
        DabValue val;
        val.kind   = kind;
        val.type   = TYPE_STRING;
        val.string = value;
        stack.push_value(val);
    }

    void push(DabValue val)
    {
        val.kind = VAL_STACK;
        stack.push_value(val);
    }

    size_t stack_position() const
    {
        return stack.size();
    }

    void push_new_frame(int n_args, int n_locals)
    {
        push(VAL_FRAME_PREV_IP, (uint64_t)ip());
        push(VAL_FRAME_PREV_STACK, (uint64_t)frame_position); // push previous frame
        frame_position = stack_position();
        push(VAL_FRAME_COUNT_ARGS, n_args);   // number of arguments
        push(VAL_FRAME_COUNT_VARS, n_locals); // number of locals
        {
            // push retvalue
            DabValue val;
            val.kind = VAL_RETVAL;
            val.type = TYPE_INVALID;
            stack.push_value(val);
        }
        for (int i = 0; i < n_locals; i++)
        {
            DabValue val;
            val.kind = VAL_VARIABLE;
            val.type = TYPE_INVALID;
            stack.push_value(val);
        }
    }

    void _dump(const char *name, const std::vector<DabValue> &data)
    {
        fprintf(stderr, "Dump of %s:\n", name);
        for (size_t i = 0; i < data.size(); i++)
        {
            fprintf(stderr, "[%4zu] ", i);
            data[i].dump();
            fprintf(stderr, "\n");
        }
    }

    size_t ip() const
    {
        return instructions.position();
    }

    void dump()
    {
        fprintf(stderr, "IP = %p (%d) Frame = %d\n", (void *)ip(), (int)ip(), (int)frame_position);
        fprintf(stderr, "Dump of functions:\n");
        for (auto it : functions)
        {
            auto &fun = it.second;
            fprintf(stderr, " - %s: %s at %p\n", fun.name.c_str(),
                    fun.regular ? "regular" : "extra", (void *)fun.address);
        }
        _dump("constants", constants);
        _dump("stack", stack._data);
    }

    int run(Stream &input)
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

    DabValue &start_of_constants()
    {
        return stack[frame_position];
    }

    DabValue &get_arg(int arg_index)
    {
        auto index = frame_position - number_of_args() - 2 + arg_index;
        return stack[index];
    }

    DabValue &get_var(int var_index)
    {
        auto index = frame_position + 3 + var_index;
        return stack[index];
    }

    DabValue &get_retval()
    {
        auto index = frame_position + 2;
        return stack[index];
    }

    size_t get_prev_ip()
    {
        return stack[frame_position - 2].fixnum;
    }

    size_t prev_frame_position()
    {
        return stack[frame_position - 1].fixnum;
    }

    int number_of_args()
    {
        return stack[frame_position + 0].fixnum;
    }

    int number_of_vars()
    {
        return stack[frame_position + 1].fixnum;
    }

    void push_constant(const DabValue &value)
    {
        constants.push_back(value);
    }

    void call(const std::string &name, int n_args)
    {
        fprintf(stderr, "VM: call <%s> with %d arguments.\n", name.c_str(), n_args);
        if (!functions.count(name))
        {
            fprintf(stderr, "VM error: Unknown function <%s>.\n", name.c_str());
            exit(1);
        }
        auto &fun = functions[name];

        if (fun.regular)
        {
            push_new_frame(n_args, fun.n_locals);
            fprintf(stderr, "VM: %s has %d local vars.\n", name.c_str(), fun.n_locals);
            instructions.seek(fun.address);
        }
        else
        {
            fun.extra();
        }
    }

    void execute(Stream &input)
    {
        while (!input.eof())
        {
            execute_single(input);
        }
    }

    void execute_single(Stream &input)
    {
        fprintf(stderr, "\n");
        dump();
        auto opcode = input.read_uint8();
        fprintf(stderr, "Opcode: %d\n", (int)opcode);
        switch (opcode)
        {
        case OP_START_FUNCTION:
        {
            auto name        = input.read_vlc_string();
            auto n_locals    = input.read_uint16();
            auto body_length = input.read_uint16();
            add_function(input, name, n_locals, body_length);
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
            stack_push_nil();
            break;
        }
        case OP_RETURN:
        {
            auto  nrets  = input.read_uint16();
            auto &retval = get_retval();
            retval       = stack_pop();
            retval.kind  = VAL_RETVAL;
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
            auto value = stack_pop();
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
        case OP_SETVAR:
        {
            auto  index = input.read_uint16();
            auto  value = stack_pop();
            auto &var   = get_var(index);
            var         = value;
            var.kind    = VAL_VARIABLE;
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
        case OP_PROPGET:
        {
            auto name  = stack_pop_symbol();
            auto value = stack_pop();
            prop_get(value, name);
            break;
        }
        default:
            fprintf(stderr, "VM error: Unknown opcode <%d>.\n", (int)opcode);
            exit(1);
            break;
        }
    }

    void prop_get(const DabValue &value, const std::string &name)
    {
        auto func = value.class_name() + "::" + name;
        stack.push_value(value);
        call(func, 1);
    }

    void kernelcall(int call)
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

    DabValue stack_pop()
    {
        auto last = stack.pop_value();
        return last;
    }

    std::string stack_pop_symbol()
    {
        auto val = stack_pop();
        if (val.type != TYPE_SYMBOL)
        {
            fprintf(stderr, "VM error: value is not a symbol.\n");
            exit(1);
        }
        return val.string;
    }

    void stack_push_nil()
    {
        DabValue val;
        val.kind = VAL_STACK;
        val.type = TYPE_NIL;
        stack.push_value(val);
    }

    void push_constant_symbol(const std::string &name)
    {
        DabValue val;
        val.kind   = VAL_CONSTANT;
        val.type   = TYPE_SYMBOL;
        val.string = name;
        push_constant(val);
    }

    void push_constant_string(const std::string &name)
    {
        DabValue val;
        val.kind   = VAL_CONSTANT;
        val.type   = TYPE_STRING;
        val.string = name;
        push_constant(val);
    }

    void push_constant_fixnum(uint64_t value)
    {
        DabValue val;
        val.kind   = VAL_CONSTANT;
        val.type   = TYPE_FIXNUM;
        val.fixnum = value;
        push_constant(val);
    }

    void push_constant_boolean(bool value)
    {
        DabValue val;
        val.kind    = VAL_CONSTANT;
        val.type    = TYPE_BOOLEAN;
        val.boolean = value;
        push_constant(val);
    }

    void add_function(Stream &input, const std::string &name, size_t n_locals, size_t body_length)
    {
        auto position = instructions.length();
        fprintf(stderr, "VM: read function <%s>.\n", name.c_str());
        DabFunction function;
        function.address  = position;
        function.n_locals = n_locals;
        function.name     = name;
        functions[name]   = function;
        instructions.append(input, body_length);
    }
};

int main()
{
    Stream input;
    byte   buffer[1024];
    while (!feof(stdin))
    {
        size_t bytes = fread(buffer, 1, 1024, stdin);
        input.append(buffer, bytes);
    }
    DabVM vm;
    return vm.run(input);
}
