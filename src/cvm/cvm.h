#pragma once

#include "../cshared/dab.h"
#include "../cshared/shared.h"
#include "../cshared/stream.h"

struct DabValue;

typedef std::function<DabValue(DabValue, std::vector<DabValue>)> dab_function_reg_t;

struct DabRuntimeError : public std::runtime_error
{
    DabRuntimeError(std::string message) : std::runtime_error("DabRuntimeError"), message(message)
    {
    }
    virtual char const *what() const throw()
    {
        return message.c_str();
    }

  private:
    std::string message;
};

struct DabCastError : public DabRuntimeError
{
    DabCastError(const char *message) : DabRuntimeError(message)
    {
    }
};

struct DabFunctionReflection
{
    std::vector<std::string> arg_names;
    std::vector<dab_class_t> arg_klasses;
    dab_class_t              ret_klass;
};

struct DabFunction
{
    bool               regular   = true;
    dab_function_reg_t extra_reg = nullptr;

    uint64_t    address = 0;
    uint64_t    length  = 0;
    std::string name;

    DabFunctionReflection reflection;

    uint64_t source_ring = 0;

    bool new_method = false;
};

enum
{
    TYPE_INVALID       = 0,
    TYPE_FIXNUM        = 1,
    TYPE_BOOLEAN       = 2,
    TYPE_NIL           = 3,
    TYPE_CLASS         = 4,
    TYPE_OBJECT        = 5,
    TYPE_ARRAY         = 6,
    TYPE_UINT8         = 7,
    TYPE_UINT16        = 8,
    TYPE_UINT32        = 9,
    TYPE_UINT64        = 10,
    TYPE_INT8          = 11,
    TYPE_INT16         = 12,
    TYPE_INT32         = 13,
    TYPE_INT64         = 14,
    TYPE_METHOD        = 15,
    TYPE_INTPTR        = 16,
    TYPE_BYTEBUFFER    = 17,
    TYPE_LITERALSTRING = 18,
    TYPE_DYNAMICSTRING = 19,
    TYPE_FLOAT         = 20,
    // TYPE_LOCALBLOCK    = 21,
    TYPE_BOX = 22,
};

#include "../cshared/classes.h"

enum
{
    REFLECT_METHOD_ARGUMENTS               = 0,
    REFLECT_METHOD_ARGUMENT_NAMES          = 1,
    REFLECT_INSTANCE_METHOD_ARGUMENT_TYPES = 2,
    REFLECT_INSTANCE_METHOD_ARGUMENT_NAMES = 3,
};

struct DabVM;
struct DabValue;

struct DabClass
{
    std::string                         name;
    dab_class_t                         index;
    bool                                builtin = false;
    std::map<dab_symbol_t, DabFunction> functions;
    std::map<dab_symbol_t, DabFunction> static_functions;
    dab_class_t                         superclass_index = CLASS_OBJECT;

    const DabFunction &get_instance_function(dab_symbol_t symbol) const;

    const DabFunction &get_static_function(dab_symbol_t symbol) const;

    void _add_reg_function(bool is_static, const std::string &func_name, dab_function_reg_t body);

    void add_static_reg_function(const std::string &func_name, dab_function_reg_t body)
    {
        _add_reg_function(true, func_name, body);
    }

    void add_reg_function(const std::string &func_name, dab_function_reg_t body)
    {
        _add_reg_function(false, func_name, body);
    }

    bool is_subclass_of(const DabClass &klass) const;

  private:
    const DabFunction &_get_function(bool _static, dab_symbol_t symbol,
                                     const DabClass &base_class) const;
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

    void retain(DabValue *value);
    void release(DabValue *value);
    void destroy(DabValue *value);
};

struct DabValueData
{
    int type = TYPE_INVALID;

    union
    {
        uint64_t _initialize = 0;

        int64_t         fixnum;
        uint8_t         num_uint8;
        uint16_t        num_uint16;
        uint32_t        num_uint32;
        uint64_t        num_uint64;
        int8_t          num_int8;
        int16_t         num_int16;
        int32_t         num_int32;
        int64_t         num_int64;
        bool            boolean;
        DabObjectProxy *object;
        void           *intptr;
        float           floatval;
    };
};

struct DabValue
{
    DabMemoryCounter<COUNTER_VALUE> _counter;
    DabValueData                    data;
    bool                            localblock = false;

    void dump(FILE *file = nullptr) const;
    void dumpex(FILE *file = nullptr) const;

    dab_class_t class_index() const;
    std::string class_name() const;
    DabClass   &get_class() const;

    void print(FILE *out, bool debug = false) const;

    bool truthy() const;

    DabValue _get_instvar(dab_symbol_t symbol);
    DabValue get_instvar(dab_symbol_t symbol);

    void set_instvar(dab_symbol_t symbol, const DabValue &value);

    void set_data(const DabValueData &other_data);

    bool is_a(const DabClass &klass) const;

    std::string print_value(bool debug = false) const;

    DabValue()
    {
    }
    DabValue(std::nullptr_t)
    {
        data.type = TYPE_NIL;
    }
    DabValue(const std::string &value) : DabValue(CLASS_DYNAMICSTRING, value.c_str())
    {
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
    DabValue(size_t class_index, bool value)
    {
        assert(class_index == CLASS_BOOLEAN);
        data.type    = TYPE_BOOLEAN;
        data.boolean = value;
    }
    DabValue(size_t class_index, uint8_t value)
    {
        assert(class_index == CLASS_UINT8);
        data.type      = TYPE_UINT8;
        data.num_uint8 = value;
    }
    DabValue(size_t class_index, uint16_t value)
    {
        assert(class_index == CLASS_UINT16);
        data.type       = TYPE_UINT16;
        data.num_uint16 = value;
    }
    DabValue(size_t class_index, uint32_t value)
    {
        assert(class_index == CLASS_UINT32);
        data.type       = TYPE_UINT32;
        data.num_uint32 = value;
    }
    DabValue(size_t class_index, int64_t value)
    {
        assert(class_index == CLASS_INT64);
        data.type      = TYPE_INT64;
        data.num_int64 = value;
    }
    DabValue(size_t class_index, uint64_t value)
    {
        if (class_index == CLASS_UINT64)
        {
            data.type       = TYPE_UINT64;
            data.num_uint64 = value;
        }
        else if (class_index == CLASS_FIXNUM)
        {
            data.type   = TYPE_FIXNUM;
            data.fixnum = value;
        }
        else
        {
            assert(false);
        }
    }
    DabValue(size_t class_index, int8_t value)
    {
        assert(class_index == CLASS_INT8);
        data.type     = TYPE_INT8;
        data.num_int8 = value;
    }
    DabValue(size_t class_index, int16_t value)
    {
        assert(class_index == CLASS_INT16);
        data.type      = TYPE_INT16;
        data.num_int16 = value;
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
    DabValue(size_t class_index, float value)
    {
        assert(class_index == CLASS_FLOAT);
        data.type     = TYPE_FLOAT;
        data.floatval = value;
    }
    DabValue(size_t class_index, const char *value)
    {
        data.type = TYPE_NIL;
        assert(class_index == CLASS_DYNAMICSTRING);
        auto obj = allocate_dynstr(value);
        std::swap(data, obj.data);
    }

    static DabValue box(DabValue base);
    static DabValue unbox(DabValue base);
    void            setbox(DabValue new_value);

    DabValue unboxed() const
    {
        if (data.type == TYPE_BOX)
        {
            return unbox(*this);
        }
        return *this;
    }

    DabValue(const DabValue &other);
    DabValue &operator=(const DabValue &other);

    ~DabValue();

    static DabValue allocate_dynstr(const char *str);

    std::vector<DabValue> &array() const;
    std::vector<uint8_t>  &bytebuffer() const;

    std::string literal_string() const;
    std::string dynamic_string() const;

    std::string string() const;

    DabValue create_instance() const;

    size_t use_count() const;
    void   retain();
    void   release();

    bool is_object() const
    {
        return data.type == TYPE_OBJECT || data.type == TYPE_ARRAY ||
               data.type == TYPE_BYTEBUFFER || data.type == TYPE_LITERALSTRING ||
               data.type == TYPE_DYNAMICSTRING;
    }
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
    std::map<dab_symbol_t, DabValue> instvars;
};

struct DabArray : public DabBaseObject
{
    std::vector<DabValue> array;
};

struct DabBox : public DabBaseObject
{
    DabValue value;
};

struct DabByteBuffer : public DabBaseObject
{
    std::vector<uint8_t> bytebuffer;
};

struct DabLiteralString : public DabBaseObject
{
    const char *pointer = nullptr;
    uint64_t    length  = 0;
};

struct DabDynamicString : public DabBaseObject
{
    std::string value;
};

struct Coverage
{
    void add_file(uint64_t hash, const std::string &filename);
    void add_line(uint64_t hash, uint64_t line);
    void dump(FILE *out = stdout) const;

  private:
    std::map<uint64_t, std::string>                  files;
    std::map<uint64_t, std::map<uint64_t, uint64_t>> lines;
};

struct DabVMReset
{
    ~DabVMReset();
};

struct DabRunOptions
{
    std::vector<FILE *> inputs = {stdin};

    bool close_file  = false;
    bool autorun     = true;
    bool extract     = false;
    bool raw         = false;
    bool autorelease = true;
    bool verbose     = false;
    //    bool with_attributes = false;
    bool leaktest = false;
    bool bare     = false;

    bool coverage_testing = false;

    FILE *output       = stdout;
    bool  close_output = false;

    std::string extract_part;

    std::string entry = "main";

    FILE *console       = stderr;
    bool  close_console = false;

    void parse(const std::vector<std::string> &args);
};

struct DabStackFrame
{
    uint64_t       prev_ip;
    DabValue       self;
    dab_register_t out_reg;
    DabValue       retvalue;

    std::vector<DabValue> args;
};

struct DabSymbol
{
    std::string value;
    uint64_t    source_ring;
};

struct DabVM
{
    DabRunOptions options;

    uint64_t last_ring_offset;

    bool       shutdown = false;
    DabVMReset reset;
    Coverage   coverage;

    Stream instructions;
    Buffer new_instructions;

    std::map<dab_symbol_t, DabFunction> functions;

    std::vector<DabSymbol> symbols;

    std::map<dab_class_t, DabClass> classes;

    std::set<uint64_t> breakpoints;

    std::vector<DabValue>              _registers;
    std::vector<std::vector<DabValue>> _register_stack;

    std::vector<DabStackFrame> stackframes;

    std::vector<BinSection> sections;

    DabClass &get_class(dab_class_t index);
    void      predefine_default_classes();
    void      define_default_classes();
    void      define_defaults();

    DabVM();
    DabVM(const DabVM &)            = delete;
    DabVM &operator=(const DabVM &) = delete;
    ~DabVM();

    std::string get_symbol(dab_symbol_t index) const;

    dab_symbol_t get_symbol_index(const std::string &string) const
    {
        for (size_t i = 0; i < symbols.size(); i++)
        {
            auto &symbol = symbols[i];
            if (symbol.value == string)
            {
                return (dab_symbol_t)i;
            }
        }
        throw DabRuntimeError("Unknown symbol: " + string);
    }

    void kernel_print(dab_register_t out_reg, std::vector<dab_register_t> reglist);
    void kernel_define_method(dab_register_t out_reg, std::vector<dab_register_t> reglist);
    void kernel_byteswap32(dab_register_t out_reg, std::vector<dab_register_t> reglist);
    void kernel_dlimport(dab_register_t out_reg, std::vector<dab_register_t> reglist);

    bool pop_frame(bool regular);

    void push_new_frame(const DabValue &self, // uint64_t block_addr,
                        dab_register_t  out_reg,
                        // const DabValue &capture,
                        std::vector<dab_register_t> reglist = {});

    void _dump(const char *name, const std::vector<DabValue> &data, FILE *output);

    uint64_t ip() const;

    int run(std::vector<Stream> &inputs);

    void load_newformat(Stream &input);

    DabStackFrame *current_frame();

    bool      has_arg(int arg_index);
    DabValue &get_arg(int arg_index);

    DabValue get_current_block();

    DabValue &get_retval();

    DabValue &get_self();

    uint64_t get_prev_ip();

    dab_register_t get_out_reg();

    int number_of_args();

    void call(dab_register_t out_reg, dab_symbol_t symbol, int n_args, dab_symbol_t block_symbol,
              const DabValue &capture, std::vector<dab_register_t> reglist = {});

    DabValue call_block(const DabValue &self, std::vector<DabValue> args);

    void _call_function(bool use_self, dab_register_t out_reg, const DabValue &self,
                        const DabFunction &fun,
                        // int n_args, // void *blockaddress,
                        // const DabValue &capture,
                        std::vector<dab_register_t> reglist = {}, DabValue *return_value = nullptr,
                        size_t stack_pos = 0);

    void execute_debug(Stream &input);

    void execute(Stream &input);

    bool execute_single(Stream &input);

    DabValue cast(const DabValue &value, dab_class_t klass_index);

    void add_class(const std::string &name, dab_class_t index, dab_class_t parent_index);

    void kernelcall(dab_register_t out_reg, int call, std::vector<dab_register_t> reglist);

    DabFunction &add_function(uint64_t address, const std::string &name, uint16_t class_index);

    void read_classes(Stream &input, uint64_t classes_address, uint64_t classes_length);

    void read_functions_ex(Stream &input, uint64_t func_address, uint64_t func_length,
                           uint64_t offset);

    void read_coverage_files(Stream &stream, uint64_t address, uint64_t length);

    void read_symbols(Stream &input, uint64_t symb_address, uint64_t symb_length, uint64_t offset);

    void instcall(const DabValue &recv, dab_symbol_t symbol, size_t n_args,
                  dab_symbol_t block_symbol = DAB_SYMBOL_NIL, const DabValue &capture = nullptr,
                  dab_register_t              outreg  = dab_register_t::nilreg(),
                  std::vector<dab_register_t> reglist = {}, DabValue *return_value = nullptr,
                  size_t stack_pos = 0);

    DabClass &define_builtin_class(const std::string &name, dab_class_t class_index,
                                   dab_class_t superclass_index = CLASS_OBJECT);

    void get_instvar(dab_symbol_t symbol, dab_register_t out_reg);
    void set_instvar(dab_symbol_t symbol, const DabValue &value);

    void extract(const std::string &name);

    DabValue merge_arrays(const DabValue &array0, const DabValue &array1);

    void reflect(size_t reflection_type, const DabValue &symbol, dab_register_t reg, bool has_class,
                 uint16_t class_index);
    void reflect_instance_method(size_t reflection_type, const DabValue &symbol, dab_register_t reg,
                                 bool has_class, uint16_t class_index);
    void reflect_method_arguments(size_t reflection_type, const DabValue &symbol,
                                  dab_register_t reg);

    void _reflect(const DabFunction &function, dab_register_t reg, bool output_names);

    DabValue register_get(dab_register_t reg_index);
    void     register_set(dab_register_t reg_index, const DabValue &value);

    bool run_leaktest(FILE *output);

    dab_symbol_t get_or_create_symbol_index(const std::string &string);

    DabValue cinstcall(DabValue self, const std::string &name, std::vector<DabValue> args = {});

    void define_default_classes_int();

    void dump_vm(FILE *out);
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
    void print_ssa_registers();

  private:
    typedef std::vector<std::pair<uint64_t, std::string>> disasm_map_t;
    disasm_map_t                                          disasm;
    bool                                                  has_disasm = false;
    void                                                  prepare_disasm();
};

#if defined(__GNUC__) && !defined(__clang__)
#define $VM __GLOBAL_VM
#endif

extern DabVM *$VM;

void setup_handlers();
