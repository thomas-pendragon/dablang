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
    uint16_t read_uint16();
    uint64_t read_uint64();

    std::string read_vlc_string();

    Buffer read_vlc_buffer();

    void append(const byte *data, size_t length);

    void append(Stream &stream, size_t length);

    void seek(size_t position);

    size_t length() const;
    size_t position() const;
    bool   eof() const;

  private:
    Buffer buffer;
    size_t _position = 0;

    byte * data() const;
    size_t remaining() const;

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
    bool regular = true;
    std::function<void(size_t, size_t)> extra = nullptr;

    size_t      address = -1;
    std::string name;
    int         n_locals = 0;
};

enum
{
    VAL_INVALID = 0,
    VAL_FRAME_PREV_IP,
    VAL_FRAME_PREV_STACK,
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
    TYPE_CLASS,
    TYPE_OBJECT,
};

enum
{
    CLASS_OBJECT         = 0,
    CLASS_STRING         = 1,
    CLASS_LITERALSTRING  = 2,
    CLASS_FIXNUM         = 3,
    CLASS_LITERALFIXNUM  = 4,
    CLASS_BOOLEAN        = 5,
    CLASS_LITERALBOOLEAN = 6,
    CLASS_NILCLASS       = 7,

    CLASS_INT_SYMBOL = 0xFE,
};

struct BaseDabVM;
struct DabValue;

struct DabClass
{
    std::string name;
    int         index;
    bool        builtin = false;
    std::map<std::string, DabFunction> functions;
    std::map<std::string, DabFunction> static_functions;
    int superclass_index = CLASS_OBJECT;

    const DabFunction &get_function(BaseDabVM &vm, const DabValue &klass,
                                    const std::string &name) const;

    const DabFunction &get_static_function(BaseDabVM &vm, const DabValue &klass,
                                           const std::string &name) const;

  private:
    const DabFunction &_get_function(bool _static, BaseDabVM &vm, const DabValue &klass,
                                     const std::string &name) const;
};

struct DabValue
{
    int kind = VAL_INVALID;
    int type = TYPE_INVALID;

    int64_t     fixnum;
    std::string string;
    bool        boolean;

    bool is_constant = false;

    void dump(BaseDabVM &vm) const;

    int         class_index() const;
    std::string class_name(BaseDabVM &vm) const;
    DabClass &get_class(BaseDabVM &vm) const;

    void print(BaseDabVM &vm, FILE *out, bool debug = false) const;

    bool truthy() const;

    DabValue()
    {
    }
    DabValue(std::nullptr_t) : type(TYPE_NIL)
    {
    }
    DabValue(const std::string &value) : type(TYPE_STRING), string(value)
    {
    }
    DabValue(const DabClass &klass) : type(TYPE_CLASS), fixnum(klass.index)
    {
    }

    DabValue create_instance() const;
};

struct Stack
{
    template <typename T>
    void push(T value, int kind = VAL_STACK)
    {
        push_value(DabValue(value), kind);
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

    void push_value(DabValue value, int kind = VAL_STACK)
    {
        value.kind = kind;
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

    DabValue &operator[](int64_t offset)
    {
        if (offset < 0)
        {
            offset = size() + offset;
        }
        if (offset >= size())
        {
            assert(false);
        }
        return _data[offset];
    }

  private:
    std::vector<DabValue> _data;
    friend class DabVM;
};

struct BaseDabVM
{
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
};

struct DabVM : public BaseDabVM
{
    void define_defaults();

    DabVM();

    void kernel_print();

    void pop_frame(bool regular);

    void push(int kind, int value);

    void push(int kind, uint64_t value);

    void push(int kind, bool value);

    void stack_push(const std::string &value);

    void stack_push(uint64_t value);

    void stack_push(bool value);

    void push(int kind, const std::string &value);

    void push(DabValue val);

    size_t stack_position() const;

    void push_new_frame(int n_args, int n_locals);

    void _dump(const char *name, const std::vector<DabValue> &data);

    size_t ip() const;

    void dump();

    int run(Stream &input);

    DabValue &start_of_constants();

    DabValue &get_arg(int arg_index);

    DabValue &get_var(int var_index);

    DabValue &get_retval();

    size_t get_prev_ip();

    size_t prev_frame_position();

    int number_of_args();

    int number_of_vars();

    void push_constant(const DabValue &value);

    void call(const std::string &name, int n_args);

    void call_function(const DabFunction &fun, int n_args);

    void execute(Stream &input);

    void execute_single(Stream &input);

    void push_class(int index);

    void add_class(const std::string &name, int index);

    void prop_get(const DabValue &value, const std::string &name);

    void call_static_instance(const DabClass &klass, const std::string &name,
                              const DabValue &object);

    void call_instance(const DabClass &klass, const std::string &name, const DabValue &object);

    void kernelcall(int call);

    std::string stack_pop_symbol();

    void push_constant_symbol(const std::string &name);

    void push_constant_string(const std::string &name);

    void push_constant_fixnum(uint64_t value);

    void push_constant_boolean(bool value);

    void add_function(Stream &input, const std::string &name, size_t n_locals, size_t body_length);
};
