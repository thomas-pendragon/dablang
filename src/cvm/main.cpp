#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <assert.h>
#include <string>
#include <vector>
#include <map>
#include <functional>

typedef unsigned char byte;

template <typename T>
T min(T a, T b)
{
    return (a < b) ? a : b;
}

struct Buffer
{
    byte * data   = nullptr;
    size_t length = 0;

    ~Buffer()
    {
        delete[] this->data;
    }

    Buffer()
    {
    }

    Buffer(const Buffer &other)
    {
        this->length = other.length;
        if (other.data)
        {
            this->data = (byte *)malloc(this->length);
            memcpy(this->data, other.data, this->length);
        }
    }

    Buffer &operator=(const Buffer &other)
    {
        delete[] this->data;
        this->length = other.length;
        if (other.data)
        {
            this->data = (byte *)malloc(this->length);
            memcpy(this->data, other.data, this->length);
        }
        return *this;
    }

    void resize(size_t new_length)
    {
        byte *new_data = (byte *)malloc(new_length);
        if (data)
        {
            memcpy(new_data, this->data, min(this->length, new_length));
        }
        delete[] this->data;
        this->data   = new_data;
        this->length = new_length;
    }

    void append(const byte *data, size_t data_length)
    {
        const size_t old_length = this->length;
        const size_t new_length = old_length + data_length;
        assert(new_length > old_length);
        resize(new_length);
        memcpy(this->data + old_length, data, data_length);
    }
};

struct Stream
{
    uint8_t read_uint8()
    {
        return _read<uint8_t>();
    }
    uint16_t read_uint16()
    {
        return _read<uint16_t>();
    }
    uint64_t read_uint64()
    {
        return _read<uint64_t>();
    }

    std::string read_vlc_string()
    {
        size_t len = read_uint8();
        if (len == 255)
        {
            len = read_uint64();
        }
        assert(len <= remaining());
        std::string ret((const char *)data(), len);
        _position += len;
        return ret;
    }

    Buffer read_vlc_buffer()
    {
        size_t len = read_uint8();
        if (len == 255)
        {
            len = read_uint64();
        }
        assert(len <= remaining());
        Buffer ret;
        ret.append(data(), len);
        _position += len;
        return ret;
    }

    void append(const byte *data, size_t length)
    {
        buffer.append(data, length);
    }

    void append(Stream &stream, size_t length)
    {
        assert(stream.remaining() >= length);
        append(stream.data(), length);
        stream._position += length;
    }

    void seek(size_t position)
    {
        assert(position < length());
        _position = position;
    }

    size_t length() const
    {
        return buffer.length;
    }
    size_t position() const
    {
        return _position;
    }
    bool eof() const
    {
        return remaining() == 0;
    }

  private:
    Buffer buffer;
    size_t _position = 0;

    byte *data() const
    {
        return buffer.data + _position;
    }
    size_t remaining() const
    {
        if (buffer.length <= _position)
            return 0;
        return buffer.length - _position;
    }

    template <typename T>
    T _read()
    {
        assert(remaining() >= sizeof(T));
        auto ret = *(T *)data();
        _position += sizeof(T);
        return ret;
    }
};

struct DabFunction
{
    bool                  regular = true;
    std::function<void()> extra   = nullptr;

    size_t      address = -1;
    std::string name;
    int         n_locals = 0;
};

enum
{
    VAL_INVALID = 0,
    VAL_FRAME_PREV_IP,
    VAL_FRAME_PREV_STACK,
    VAL_FRAME_START_CONST,
    VAL_FRAME_COUNT_CONST,
    VAL_FRAME_COUNT_ARGS,
    VAL_FRAME_COUNT_VARS,
    VAL_RETVAL,
    VAL_CONSTANT,
    VAL_VARIABLE,
    VAL_STACK,
};

enum
{
    TYPE_INVALID = 0,
    TYPE_FIXNUM,
    TYPE_STRING,
    TYPE_BOOLEAN,
    TYPE_NIL,
    TYPE_SYMBOL,
};

struct DabValue
{
    int kind = VAL_INVALID;
    int type = TYPE_INVALID;

    int64_t     fixnum;
    std::string string;
    bool        boolean;

    void dump() const
    {
        static const char *kinds[] = {"INVAL", "PrvIP", "PrvSP", "sCnst", "nCnst", "nArgs",
                                      "nVars", "RETVL", "CONST", "VARIA", "STACK"};
        static const char *types[] = {
            "INVA", "FIXN", "STRI", "BOOL", "NIL ", "SYMB",
        };
        fprintf(stderr, "%s %s ", kinds[kind], types[type]);
        print(stderr, true);
    }

    void print(FILE *out, bool debug = false) const
    {
        switch (type)
        {
        case TYPE_FIXNUM:
            fprintf(out, "%zd", fixnum);
            break;
        case TYPE_STRING:
            fprintf(out, debug ? "\"%s\"" : "%s", string.c_str());
            break;
        case TYPE_SYMBOL:
            fprintf(out, ":%s", string.c_str());
            break;
        case TYPE_BOOLEAN:
            fprintf(out, "%s", boolean ? "true" : "false");
            break;
        case TYPE_NIL:
            fprintf(out, "nil");
            break;
        default:
            fprintf(out, "?");
            break;
        }
    }

    bool truthy() const
    {
        switch (type)
        {
        case TYPE_FIXNUM:
            return fixnum;
        case TYPE_STRING:
            return string.length();
            break;
        case TYPE_SYMBOL:
            return true;
            break;
        case TYPE_BOOLEAN:
            return boolean;
            break;
        case TYPE_NIL:
            return false;
            break;
        default:
            return false;
            break;
        }
    }
};

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
    std::vector<DabValue> stack;
    std::vector<DabValue> constants;

    DabVM()
    {
        DabFunction print_fun;
        print_fun.name    = "print";
        print_fun.regular = false;
        print_fun.extra   = [this]() {
            auto arg = stack_pop();
            fprintf(stderr, "[ ");
            arg.print(stderr);
            fprintf(stderr, " ]\n");
            arg.print(stdout);
            stack_push_nil();
        };
        functions["print"] = print_fun;

        DAB_DEFINE_OP_STR(+);
        DAB_DEFINE_OP(-);
        DAB_DEFINE_OP(*);
        DAB_DEFINE_OP(/);
        DAB_DEFINE_OP(%);
        DAB_DEFINE_OP_BOOL(==);
    }

    void pop_frame(bool regular)
    {
        int    frame_loc = frame_position;
        int    n_args    = number_of_args();
        int    n_const   = number_of_constants().fixnum;
        size_t prev_pos  = prev_frame_position();
        auto   retval    = get_retval();
        auto   prev_ip   = get_prev_ip();

        if (prev_pos == -1)
        {
            exit(0);
        }

        for (int i = 0; i < n_const; i++)
            constants.pop_back();

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
        stack.push_back(val);
    }

    void push(int kind, uint64_t value)
    {
        DabValue val;
        val.kind   = kind;
        val.type   = TYPE_FIXNUM;
        val.fixnum = value;
        stack.push_back(val);
    }

    void push(int kind, bool value)
    {
        DabValue val;
        val.kind    = kind;
        val.type    = TYPE_BOOLEAN;
        val.boolean = value;
        stack.push_back(val);
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
        stack.push_back(val);
    }

    void push(DabValue val)
    {
        val.kind = VAL_STACK;
        stack.push_back(val);
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
        push(VAL_FRAME_START_CONST, (uint64_t)constants.size()); // start of constants
        push(VAL_FRAME_COUNT_CONST, 0);                          // number of constants
        push(VAL_FRAME_COUNT_ARGS, n_args);                      // number of arguments
        push(VAL_FRAME_COUNT_VARS, n_locals);                    // number of locals
        {
            // push retvalue
            DabValue val;
            val.kind = VAL_RETVAL;
            val.type = TYPE_INVALID;
            stack.push_back(val);
        }
        for (int i = 0; i < n_locals; i++)
        {
            DabValue val;
            val.kind = VAL_VARIABLE;
            val.type = TYPE_INVALID;
            stack.push_back(val);
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
        _dump("stack", stack);
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
        auto index = frame_position + 5 + var_index;
        return stack[index];
    }

    DabValue &get_retval()
    {
        auto index = frame_position + 4;
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

    DabValue &number_of_constants()
    {
        return stack[frame_position + 1];
    }

    int number_of_args()
    {
        return stack[frame_position + 2].fixnum;
    }

    int number_of_vars()
    {
        return stack[frame_position + 3].fixnum;
    }

    void push_constant(const DabValue &value)
    {
        constants.push_back(value);
        auto &ref = number_of_constants();
        ref.fixnum += 1;
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
                push(constants[start_of_constants().fixnum + index]);
                break;
            }
            case OP_CALL:
            {
                auto name   = stack_pop_symbol();
                auto n_args = input.read_uint16();
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
            default:
                fprintf(stderr, "VM error: Unknown opcode <%d>.\n", (int)opcode);
                exit(1);
                break;
            }
        }
    }

    DabValue stack_pop()
    {
        if (stack.size() == 0)
        {
            fprintf(stderr, "VM error: empty stack.\n");
            exit(1);
        }
        auto last = stack[stack.size() - 1];
        stack.pop_back();
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
        stack.push_back(val);
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
