#pragma once

#include "../cshared/shared.h"

struct Buffer
{
    byte * data   = nullptr;
    size_t length = 0;

    Buffer();
    Buffer(const Buffer &other);
    ~Buffer();
    Buffer &operator=(const Buffer &other);
    void resize(size_t new_length);
    void append(const byte *data, size_t data_length);
};

struct Stream
{
    uint8_t  read_uint8();
    int16_t  read_int16();
    int32_t  read_int32();
    uint16_t read_uint16();
    uint32_t read_uint32();
    uint64_t read_uint64();
    int16_t  read_reg();

    std::vector<int16_t> read_reglist();

    std::string read_vlc_string();

    Buffer read_vlc_buffer();

    void append(const byte *data, size_t length);

    void append(Stream &stream)
    {
        append(stream, stream.remaining());
    }
    void append(Stream &stream, size_t length);

    void seek(size_t position);

    size_t length() const;
    size_t position() const;
    bool   eof() const;

    void rewind()
    {
        seek(0);
    }

    size_t remaining() const;

    const byte *raw_base_data() const
    {
        return buffer.data;
    }
    size_t raw_base_length() const
    {
        return buffer.length;
    }

  private:
    Buffer buffer;
    size_t _position = 0;

    byte *data() const;

    template <typename T>
    T _read()
    {
        assert(remaining() >= sizeof(T));
        auto ret = *(T *)data();
        _position += sizeof(T);
        return ret;
    }
};

struct DabValue;

typedef std::function<void(size_t, size_t, void *)> dab_function_t;
typedef std::function<DabValue(DabValue)> dab_simple_function_t;

struct DabFunctionReflection
{
    std::vector<std::string> arg_names;
    std::vector<size_t>      arg_klasses;
    size_t                   ret_klass;
};

struct DabFunction
{
    bool           regular = true;
    dab_function_t extra   = nullptr;

    size_t      address = -1;
    std::string name;

    DabFunctionReflection reflection;
};

enum
{
    TYPE_INVALID = 0,
    TYPE_FIXNUM,
    TYPE_STRING,
    TYPE_BOOLEAN,
    TYPE_NIL,
    TYPE_SYMBOL,
    TYPE_CLASS,
    TYPE_OBJECT,
    TYPE_ARRAY,
    TYPE_UINT8,
    TYPE_UINT32,
    TYPE_UINT64,
    TYPE_INT32,
    TYPE_METHOD,
    TYPE_INTPTR,
    TYPE_BYTEBUFFER,
};

#include "../cshared/classes.h"

enum
{
    CLASS_INT_SYMBOL = 0xFE,
};

enum
{
    REFLECT_METHOD_ARGUMENTS      = 0,
    REFLECT_METHOD_ARGUMENT_NAMES = 1,
};

struct DabVM;
struct DabValue;

struct DabClass
{
    std::string name;
    int         index;
    bool        builtin = false;
    std::map<std::string, DabFunction> functions;
    std::map<std::string, DabFunction> static_functions;
    int superclass_index = CLASS_OBJECT;

    const DabFunction &get_function(const DabValue &klass, const std::string &name) const;

    const DabFunction &get_static_function(const DabValue &klass, const std::string &name) const;

    void add_function(const std::string &name, dab_function_t body);
    void add_static_function(const std::string &name, dab_function_t body);

    void add_simple_function(const std::string &name, dab_simple_function_t body);

    bool is_subclass_of(const DabClass &klass) const;

  private:
    const DabFunction &_get_function(bool _static, const DabValue &klass,
                                     const std::string &name) const;
};

enum
{
    COUNTER_OBJECT = 1,
    COUNTER_PROXY  = 2,
    COUNTER_VALUE  = 3,
};

template <int type>
struct DabMemoryCounter
{
    DabMemoryCounter()
    {
        _counter()++;
    }
    ~DabMemoryCounter()
    {
        _counter()--;
    }
    static size_t counter()
    {
        return _counter();
    }

  private:
    static size_t &_counter()
    {
        static size_t counter = 0;
        return counter;
    }
};

struct DabBaseObject;

struct DabObjectProxy
{
    DabMemoryCounter<COUNTER_PROXY> _counter;

    DabBaseObject *object;
    size_t         count_strong;
    bool           destroying = false;

    void retain();
    void release(DabValue *value);
    void destroy(DabValue *value);
};

struct DabValueData
{
    int type = TYPE_INVALID;

    int64_t         fixnum     = 0;
    uint8_t         num_uint8  = 0;
    uint32_t        num_uint32 = 0;
    uint64_t        num_uint64 = 0;
    int32_t         num_int32  = 0;
    std::string     string;
    bool            boolean = false;
    DabObjectProxy *object  = nullptr;
    void *          intptr  = nullptr;

    bool is_constant = false;
};

struct DabValue
{
    DabMemoryCounter<COUNTER_VALUE> _counter;
    DabValueData                    data;

    void dump(FILE *file = stderr) const;

    int         class_index() const;
    std::string class_name() const;
    DabClass &  get_class() const;

    void print(FILE *out, bool debug = false) const;

    bool truthy() const;

    DabValue _get_instvar(const std::string &name);
    DabValue get_instvar(const std::string &name);

    void set_instvar(const std::string &name, const DabValue &value);

    void set_data(const DabValueData &other_data);

    bool is_a(const DabClass &klass) const;

    DabValue()
    {
    }
    DabValue(std::nullptr_t)
    {
        data.type = TYPE_NIL;
    }
    DabValue(const std::string &value)
    {
        data.type   = TYPE_STRING;
        data.string = value;
    }
    DabValue(const DabClass &klass)
    {
        data.type   = TYPE_CLASS;
        data.fixnum = klass.index;
    }
    DabValue(uint64_t value)
    {
        data.type   = TYPE_FIXNUM;
        data.fixnum = value;
    }
    DabValue(bool value)
    {
        data.type    = TYPE_BOOLEAN;
        data.boolean = value;
    }
    DabValue(size_t class_index, uint8_t value)
    {
        assert(class_index == CLASS_UINT8);
        data.type      = TYPE_UINT8;
        data.num_uint8 = value;
    }
    DabValue(size_t class_index, uint32_t value)
    {
        assert(class_index == CLASS_UINT32);
        data.type       = TYPE_UINT32;
        data.num_uint32 = value;
    }
    DabValue(size_t class_index, uint64_t value)
    {
        assert(class_index == CLASS_UINT64);
        data.type       = TYPE_UINT64;
        data.num_uint64 = value;
    }
    DabValue(size_t class_index, int32_t value)
    {
        assert(class_index == CLASS_INT32);
        data.type      = TYPE_INT32;
        data.num_int32 = value;
    }
    DabValue(size_t class_index, void *value)
    {
        assert(class_index == CLASS_INTPTR);
        data.type   = TYPE_INTPTR;
        data.intptr = value;
    }

    DabValue(const DabValue &other);
    DabValue &operator=(const DabValue &other);

    ~DabValue();

    std::vector<DabValue> &array() const;
    std::vector<uint8_t> & bytebuffer() const;

    DabValue create_instance() const;

    size_t use_count() const;
    void   retain();
    void   release();
};

struct DabBaseObject
{
    DabMemoryCounter<COUNTER_OBJECT> _counter;
    uint64_t                         klass;
    virtual ~DabBaseObject()
    {
    }
};

struct DabObject : public DabBaseObject
{
    std::map<std::string, DabValue> instvars;
};

struct DabArray : public DabBaseObject
{
    std::vector<DabValue> array;
};

struct DabByteBuffer : public DabBaseObject
{
    std::vector<uint8_t> bytebuffer;
};

struct Stack
{
    void push(DabValue value)
    {
        push_value(value);
    }

    void push_nil()
    {
        push(nullptr);
    }

    DabValue pop_value()
    {
        if (!size())
        {
            fprintf(stderr, "VM error: empty stack.\n");
            exit(1);
        }
        auto ret = _data[_data.size() - 1];
        _data.pop_back();
        return ret;
    }

    void push_value(DabValue value)
    {
        _data.push_back(value);
    }

    void resize(size_t size)
    {
        _data.resize(size);
    }

    size_t size() const
    {
        return _data.size();
    }

    std::string pop_symbol()
    {
        auto val = pop_value();
        if (val.data.type != TYPE_SYMBOL)
        {
            fprintf(stderr, "VM error: value is not a symbol.\n");
            exit(1);
        }
        return val.data.string;
    }

    DabValue &operator[](int64_t offset)
    {
        if (offset < 0)
        {
            offset = size() + offset;
        }
        if (offset >= (int64_t)size())
        {
            assert(false);
        }
        return _data[offset];
    }

  private:
    std::vector<DabValue> _data;
    friend struct DabVM;
    friend struct DabVM_debug;
};

struct Coverage
{
    void add_file(uint64_t hash, const std::string &filename);
    void add_line(uint64_t hash, uint64_t line);
    void dump(FILE *out = stdout) const;

  private:
    std::map<uint64_t, std::string> files;
    std::map<uint64_t, std::map<uint64_t, uint64_t>> lines;
};

struct DabVMReset
{
    ~DabVMReset();
};

struct DabVM
{
    bool       autorelease     = true;
    bool       shutdown        = false;
    bool       verbose         = false;
    bool       with_attributes = false;
    DabVMReset reset;
    Coverage   coverage;
    bool       coverage_testing;

    Stream instructions;
    std::map<std::string, DabFunction> functions;
    size_t                frame_position = -1;
    Stack                 stack;
    std::vector<DabValue> constants;
    std::map<int, DabClass> classes;

    std::set<size_t> breakpoints;

    std::vector<DabValue>              ssa_registers;
    std::vector<std::vector<DabValue>> ssa_register_stack;

    DabClass &get_class(int index)
    {
        if (!classes.count(index))
        {
            fprintf(stderr, "VM error: unknown class with index <0x%04x>.\n", index);
            exit(1);
        }
        return classes[index];
    }
    void define_default_classes();
    void define_defaults();

    DabVM();
    DabVM(const DabVM &) = delete;
    DabVM &operator=(const DabVM &) = delete;
    ~DabVM();

    std::string get_symbol(size_t index) const
    {
        assert(index < constants.size());
        const auto &val = constants[index];
        if (val.data.type != TYPE_SYMBOL)
        {
            fprintf(stderr, "VM error: value is not a symbol.\n");
            exit(1);
        }
        return val.data.string;
    }

    void kernel_print(int out_reg);

    bool pop_frame(bool regular);

    size_t stack_position() const;

    void push_new_frame(const DabValue &self, int n_args, uint64_t block_addr, int out_reg);

    void _dump(const char *name, const std::vector<DabValue> &data, FILE *output);

    size_t ip() const;

    int run(Stream &input, bool autorun, bool raw, bool coverage_testing);

    DabValue &get_arg(int arg_index);

    size_t    get_varcount();
    DabValue &get_var(int var_index);

    DabValue &get_retval();

    DabValue &get_self();

    size_t get_prev_ip();

    size_t prev_frame_position();

    uint64_t get_block_addr();
    int      get_out_reg();

    int number_of_args();

    void push_constant(const DabValue &value);

    void call(int out_reg, const std::string &name, int n_args, const std::string &block_name);

    void call_function(int out_reg, const DabValue &self, const DabFunction &fun, int n_args);
    void call_function_block(int out_reg, const DabValue &self, const DabFunction &fun, int n_args,
                             const DabFunction &blockfun);

    void _call_function(int out_reg, const DabValue &self, const DabFunction &fun, int n_args,
                        void *blockaddress);

    void execute_debug(Stream &input);

    void execute(Stream &input);

    bool execute_single(Stream &input);

    void push_class(int index);

    DabValue cast(const DabValue &value, int klass_index);

    void add_class(const std::string &name, int index, int parent_index);

    void call_static_instance(const DabClass &klass, const std::string &name,
                              const DabValue &object);

    void kernelcall(int out_reg, int call);

    void push_constant_symbol(const std::string &name);

    void push_constant_string(const std::string &name);

    void push_constant_fixnum(uint64_t value);

    void push_method(const std::string &name);

    void add_function(size_t address, const std::string &name, uint16_t class_index);

    void instcall(const DabValue &recv, const std::string &name, size_t n_args, size_t n_rets,
                  const std::string &block_name = "");

    DabClass &define_builtin_class(const std::string &name, size_t class_index,
                                   size_t superclass_index = CLASS_OBJECT);

    void get_instvar(const std::string &name);
    void set_instvar(const std::string &name, const DabValue &value);
    void push_array(size_t n);

    void extract(const std::string &name);

    void yield(void *block_addr, const std::vector<DabValue> arguments);

    DabValue merge_arrays(const DabValue &array0, const DabValue &array1);

    void reflect(size_t reflection_type, const DabValue &symbol);
    void reflect_method_arguments(size_t reflection_type, const DabValue &symbol);

    void set_ssa(size_t ssa_index, const DabValue &value);
};

struct DabVM_debug
{
    DabVM &vm;
    DabVM_debug(DabVM &vm) : vm(vm)
    {
    }
    void print_registers();
    void print_classes();
    void print_functions();
    void print_constants();
    void print_stack();
    void print_code(bool current_only);

  private:
    typedef std::vector<std::pair<size_t, std::string>> disasm_map_t;
    disasm_map_t disasm;
    bool         has_disasm = false;
    void         prepare_disasm();
};

#if defined(__GNUC__) && !defined(__clang__)
#define $VM __GLOBAL_VM
#endif

extern DabVM *$VM;

void setup_handlers();
