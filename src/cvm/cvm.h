#pragma once

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <assert.h>
#include <string>
#include <vector>
#include <map>
#include <functional>
#include <algorithm>
#include <cctype>

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
    uint16_t read_uint16();
    uint64_t read_uint64();

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

typedef std::function<void(size_t, size_t)> dab_function_t;
typedef std::function<DabValue(DabValue)> dab_simple_function_t;

struct DabFunction
{
    bool           regular = true;
    dab_function_t extra   = nullptr;

    size_t      address = -1;
    std::string name;
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
};

enum
{
    CLASS_OBJECT        = 0,
    CLASS_STRING        = 1,
    CLASS_LITERALSTRING = 2,
    CLASS_FIXNUM        = 3,
    CLASS_LITERALFIXNUM = 4,
    CLASS_BOOLEAN       = 5,
    CLASS_NILCLASS      = 6,
    CLASS_ARRAY         = 7,

    CLASS_INT_SYMBOL = 0xFE,
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

    const DabFunction &get_function(DabVM &vm, const DabValue &klass,
                                    const std::string &name) const;

    const DabFunction &get_static_function(DabVM &vm, const DabValue &klass,
                                           const std::string &name) const;

    void add_function(const std::string &name, dab_function_t body);
    void add_static_function(const std::string &name, dab_function_t body);

    void add_simple_function(DabVM &vm, const std::string &name, dab_simple_function_t body);

  private:
    const DabFunction &_get_function(bool _static, DabVM &vm, const DabValue &klass,
                                     const std::string &name) const;
};

struct DabBaseObject;

struct DabObjectProxy
{
    DabBaseObject *object;
    size_t         count_strong;

    void retain();
    void release();
};

struct DabValueData
{
    int type = TYPE_INVALID;

    int64_t         fixnum;
    std::string     string;
    bool            boolean;
    DabObjectProxy *object = nullptr;

    bool is_constant = false;
};

struct DabValue
{
    DabValueData data;

    void dump(DabVM &vm, FILE *file = stderr) const;

    int         class_index() const;
    std::string class_name(DabVM &vm) const;
    DabClass &get_class(DabVM &vm) const;

    void print(DabVM &vm, FILE *out, bool debug = false) const;

    bool truthy() const;

    DabValue _get_instvar(DabVM &vm, const std::string &name);
    DabValue get_instvar(DabVM &vm, const std::string &name);

    void set_instvar(DabVM &vm, const std::string &name, const DabValue &value);

    void set_data(const DabValueData &other_data);

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

    DabValue(const DabValue &other);
    DabValue &operator=(const DabValue &other);

    ~DabValue();

    std::vector<DabValue> &array() const;

    DabValue create_instance() const;
};

struct DabBaseObject
{
    uint64_t klass;
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

struct DabVM
{
    Coverage coverage;
    bool     coverage_testing;

    Stream instructions;
    std::map<std::string, DabFunction> functions;
    size_t                frame_position = -1;
    Stack                 stack;
    std::vector<DabValue> constants;
    std::map<int, DabClass> classes;

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

    void kernel_print();

    bool pop_frame(bool regular);

    size_t stack_position() const;

    void push_new_frame(const DabValue &self, int n_args);

    void _dump(const char *name, const std::vector<DabValue> &data);

    size_t ip() const;

    int run(Stream &input, bool autorun, bool raw, bool coverage_testing);

    DabValue &get_arg(int arg_index);

    DabValue &get_var(int var_index);

    DabValue &get_retval();

    DabValue &get_self();

    size_t get_prev_ip();

    size_t prev_frame_position();

    int number_of_args();

    void push_constant(const DabValue &value);

    void call(const std::string &name, int n_args);

    void call_function(const DabValue &self, const DabFunction &fun, int n_args);

    void execute_debug(Stream &input);

    void execute(Stream &input);

    bool execute_single(Stream &input);

    void push_class(int index);

    void add_class(const std::string &name, int index);

    void call_static_instance(const DabClass &klass, const std::string &name,
                              const DabValue &object);

    void kernelcall(int call);

    void push_constant_symbol(const std::string &name);

    void push_constant_string(const std::string &name);

    void push_constant_fixnum(uint64_t value);

    void add_function(size_t address, const std::string &name, uint16_t class_index);

    void instcall(const DabValue &recv, const std::string &name, size_t n_args, size_t n_rets);

    DabClass &define_builtin_class(const std::string &name, size_t class_index,
                                   size_t superclass_index = CLASS_OBJECT);

    void get_instvar(const std::string &name);
    void set_instvar(const std::string &name, const DabValue &value);
    void push_array(size_t n);

    void extract(const std::string &name);
};
