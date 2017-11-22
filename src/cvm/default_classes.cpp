#include "cvm.h"

#define STR2(s) #s
#define STR(s) STR2(s)

#define DAB_MEMBER_OPERATOR(klass, cast_to, operator, result_class, result_type, member)           \
    klass.add_function(STR(operator), [](size_t n_args, size_t n_ret, void *blockaddr) {           \
        assert(n_args == 2);                                                                       \
        assert(n_ret == 1);                                                                        \
        assert(blockaddr == 0);                                                                    \
        auto &stack = $VM->stack;                                                                  \
        auto  arg0  = stack.pop_value();                                                           \
        auto  arg1  = $VM->cast(stack.pop_value(), cast_to);                                       \
        auto v0     = arg0 member;                                                                 \
        auto v1     = arg1 member;                                                                 \
                                                                                                   \
        DabValue ret(result_class, (result_type)(v0 operator v1));                                 \
        stack.push(ret);                                                                           \
    })

#define DAB_MEMBER_EQ_OPERATOR(klass, cast_to, operator, result_class, result_type, member)        \
    klass.add_function(STR(operator), [](size_t n_args, size_t n_ret, void *blockaddr) {           \
        assert(n_args == 2);                                                                       \
        assert(n_ret == 1);                                                                        \
        assert(blockaddr == 0);                                                                    \
        auto &   stack = $VM->stack;                                                               \
        auto     arg0  = stack.pop_value();                                                        \
        auto     arg1  = stack.pop_value();                                                        \
        DabValue ret;                                                                              \
        try                                                                                        \
        {                                                                                          \
            arg1    = $VM->cast(arg1, cast_to);                                                    \
            auto v0 = arg0 member;                                                                 \
            auto v1 = arg1 member;                                                                 \
            ret     = DabValue(result_class, (result_type)(v0 operator v1));                       \
        }                                                                                          \
        catch (DabCastError & error)                                                               \
        {                                                                                          \
            ret = DabValue(result_class, (bool)(true operator false));                             \
        }                                                                                          \
        stack.push(ret);                                                                           \
    })

#define DAB_MEMBER_EQUALS_OPERATORS(klass, cast_to, member)                                        \
    DAB_MEMBER_EQ_OPERATOR(klass, cast_to, ==, CLASS_BOOLEAN, bool, member);                       \
    DAB_MEMBER_EQ_OPERATOR(klass, cast_to, !=, CLASS_BOOLEAN, bool, member)

#define DAB_MEMBER_COMPARE_OPERATORS(klass, cast_to, member)                                       \
    DAB_MEMBER_OPERATOR(klass, cast_to, >, CLASS_BOOLEAN, bool, member);                           \
    DAB_MEMBER_OPERATOR(klass, cast_to, >=, CLASS_BOOLEAN, bool, member);                          \
    DAB_MEMBER_OPERATOR(klass, cast_to, <=, CLASS_BOOLEAN, bool, member);                          \
    DAB_MEMBER_OPERATOR(klass, cast_to, <, CLASS_BOOLEAN, bool, member)

#define DAB_MEMBER_NUMERIC_OPERATORS(klass, cast_to, result_type, member)                          \
    DAB_MEMBER_EQUALS_OPERATORS(klass, cast_to, member);                                           \
    DAB_MEMBER_COMPARE_OPERATORS(klass, cast_to, member);                                          \
    DAB_MEMBER_OPERATOR(klass, cast_to, +, cast_to, result_type, member);                          \
    DAB_MEMBER_OPERATOR(klass, cast_to, -, cast_to, result_type, member);                          \
    DAB_MEMBER_OPERATOR(klass, cast_to, *, cast_to, result_type, member);                          \
    DAB_MEMBER_OPERATOR(klass, cast_to, /, cast_to, result_type, member);                          \
    DAB_MEMBER_OPERATOR(klass, cast_to, %, cast_to, result_type, member);                          \
    DAB_MEMBER_OPERATOR(klass, cast_to, <<, cast_to, result_type, member);                         \
    DAB_MEMBER_OPERATOR(klass, cast_to, >>, cast_to, result_type, member);                         \
    DAB_MEMBER_OPERATOR(klass, cast_to, |, cast_to, result_type, member);                          \
    DAB_MEMBER_OPERATOR(klass, cast_to, &, cast_to, result_type, member)

static int32_t byteswap(int32_t value)
{
    return ((value >> 24) & 0x000000FF) | ((value << 8) & 0x00FF0000) |
           ((value >> 8) & 0x0000FF00) | ((value << 24) & 0xFF000000);
}

DabClass &DabVM::define_builtin_class(const std::string &name, size_t class_index,
                                      size_t superclass_index)
{
    DabClass klass;
    klass.index            = class_index;
    klass.name             = name;
    klass.builtin          = true;
    klass.superclass_index = superclass_index;
    classes[class_index]   = klass;
    return classes[class_index];
}

void DabVM::predefine_default_classes()
{
    fprintf(stderr, "vm: predefine default classes\n");

    define_builtin_class("Object", CLASS_OBJECT);
    define_builtin_class("String", CLASS_STRING);
    define_builtin_class("Fixnum", CLASS_FIXNUM);
    define_builtin_class("Boolean", CLASS_BOOLEAN);
    define_builtin_class("NilClass", CLASS_NILCLASS);
    define_builtin_class("Array", CLASS_ARRAY);
    define_builtin_class("Uint8", CLASS_UINT8, CLASS_FIXNUM);
    define_builtin_class("Uint16", CLASS_UINT16, CLASS_FIXNUM);
    define_builtin_class("Uint32", CLASS_UINT32, CLASS_FIXNUM);
    define_builtin_class("Uint64", CLASS_UINT64, CLASS_FIXNUM);
    define_builtin_class("Int8", CLASS_INT8, CLASS_FIXNUM);
    define_builtin_class("Int16", CLASS_INT16, CLASS_FIXNUM);
    define_builtin_class("Int32", CLASS_INT32, CLASS_FIXNUM);
    define_builtin_class("Int64", CLASS_INT64, CLASS_FIXNUM);
    define_builtin_class("Method", CLASS_METHOD);
    define_builtin_class("IntPtr", CLASS_INTPTR);
    define_builtin_class("ByteBuffer", CLASS_BYTEBUFFER);
    define_builtin_class("LiteralString", CLASS_LITERALSTRING, CLASS_STRING);
}

void DabVM::define_default_classes()
{
    fprintf(stderr, "vm: define default classes\n");

    auto &object_class = get_class(CLASS_OBJECT);
    object_class.add_static_reg_function("new", [this](DabValue self, std::vector<DabValue>) {
        auto arg = self;
        assert(arg.data.type == TYPE_CLASS);
        auto instance = arg.create_instance();

        auto stack_pos = stack.size() + 1;

        instcall(instance, "__construct", 0);

        // temporary hack
        while (stack.size() != stack_pos)
        {
            execute_single(instructions);
        }

        stack.pop_value();
        return instance;
    });
    object_class.add_reg_function(
        "class", [](DabValue self, std::vector<DabValue>) { return self.get_class(); });
    object_class.add_simple_function("to_s", [](DabValue self) { return self.print_value(); });
    object_class.add_simple_function("__construct", [](DabValue) { return nullptr; });
    object_class.add_simple_function("__destruct", [](DabValue) { return nullptr; });
    object_class.add_function("is", [](size_t n_args, size_t n_ret, void *blockaddr) {
        assert(blockaddr == 0);
        assert(n_args == 2);
        assert(n_ret == 1);
        auto &stack = $VM->stack;
        auto  arg0  = stack.pop_value();
        auto  arg1  = stack.pop_value();
        stack.push_value(arg0.is_a(arg1.get_class()));
    });
    object_class.add_static_function("to_s", [](size_t n_args, size_t n_ret, void *blockaddr) {
        assert(blockaddr == 0);
        assert(n_args == 1);
        assert(n_ret == 1);
        auto &stack = $VM->stack;
        auto  arg   = stack.pop_value();
        stack.push_value(arg.class_name());
    });
    object_class.add_static_reg_function("==", [](DabValue self, std::vector<DabValue> args) {
        assert(args.size() == 1);
        auto arg0 = self;
        auto arg1 = args[0];
        assert(arg0.data.type == TYPE_CLASS);
        assert(arg1.data.type == TYPE_CLASS);
        return DabValue(arg0.data.fixnum == arg1.data.fixnum);
    });

    auto &string_class = get_class(CLASS_STRING);
    string_class.add_reg_function("upcase", [](DabValue self, std::vector<DabValue> args) {
        assert(args.size() == 0);
        auto s = self.string();
        std::transform(s.begin(), s.end(), s.begin(), ::toupper);
        return s;
    });
    string_class.add_reg_function("length", [](DabValue self, std::vector<DabValue> args) {
        assert(args.size() == 0);
        auto     s = self.string();
        DabValue ret(CLASS_INT32, (int)s.size());
        return ret;
    });
    string_class.add_reg_function("[]", [](DabValue self, std::vector<DabValue> args) {
        assert(args.size() == 1);
        auto arg = $VM->cast(args[0], CLASS_FIXNUM);
        auto s   = self.string();
        auto n   = arg.data.fixnum;
        return DabValue(s.substr(n, 1));
    });
    string_class.add_reg_function("+", [](DabValue self, std::vector<DabValue> args) {
        assert(args.size() == 1);
        auto arg0 = self;
        auto arg1 = $VM->cast(args[0], CLASS_STRING);
        auto s0   = arg0.string();
        auto s1   = arg1.string();
        return DabValue(s0 + s1);
    });
    string_class.add_static_reg_function("new", [](DabValue, std::vector<DabValue> args) {
        auto argc = args.size();
        assert(argc <= 2);
        DabValue ret_value;
        ret_value.data.type = TYPE_STRING;
        if (argc == 2)
        {
            auto        arg1   = $VM->cast(args[0], CLASS_BYTEBUFFER);
            auto        arg2   = $VM->cast(args[1], CLASS_FIXNUM);
            const auto &buffer = arg1.bytebuffer();
            const auto  length = arg2.data.fixnum;
            if (length)
            {
                ret_value.data.legacy_string = std::string((const char *)&buffer[0], length);
            }
        }
        else if (argc == 1)
        {
            ret_value.data.legacy_string = args[0].string();
        }
        return ret_value;
    });
    string_class.add_simple_function("to_s", [](DabValue self) { return self; });
    DAB_MEMBER_EQUALS_OPERATORS(string_class, CLASS_STRING, .string());
    DAB_MEMBER_COMPARE_OPERATORS(string_class, CLASS_STRING, .string());

    auto &fixnum_class = get_class(CLASS_FIXNUM);
    fixnum_class.add_static_function("new", [](size_t n_args, size_t n_ret, void *blockaddr) {
        assert(blockaddr == 0);
        assert(n_args == 1 || n_args == 2);
        assert(n_ret == 1);
        auto &   stack = $VM->stack;
        auto     klass = stack.pop_value();
        DabValue ret_value;
        ret_value.data.type   = TYPE_FIXNUM;
        ret_value.data.fixnum = 0;
        if (n_args == 2)
        {
            auto arg = stack.pop_value();
            assert(arg.data.type == TYPE_FIXNUM);
            ret_value.data.fixnum = arg.data.fixnum;
        }
        stack.push_value(ret_value);
    });
    DAB_MEMBER_NUMERIC_OPERATORS(fixnum_class, CLASS_FIXNUM, uint64_t, .data.fixnum);

    auto &intptr_class = get_class(CLASS_INTPTR);
    intptr_class.add_simple_function("fetch_int32", [](DabValue self) {
        auto     ptr   = self.data.intptr;
        auto     iptr  = (int32_t *)ptr;
        auto     value = *iptr;
        DabValue ret(CLASS_INT32, value);
        return ret;
    });

#define CREATE_INT_CLASS(small, Title, BIG)                                                        \
    auto &small##_class = get_class(CLASS_##BIG);                                                  \
    DAB_MEMBER_NUMERIC_OPERATORS(small##_class, CLASS_##BIG, small##_t, .data.num_##small);

    CREATE_INT_CLASS(uint8, Uint8, UINT8);
    CREATE_INT_CLASS(uint16, Uint16, UINT16);
    CREATE_INT_CLASS(uint32, Uint32, UINT32);
    CREATE_INT_CLASS(uint64, Uint64, UINT64);

    CREATE_INT_CLASS(int8, Int8, INT8);
    CREATE_INT_CLASS(int16, Int16, INT16);
    CREATE_INT_CLASS(int32, Int32, INT32);
    CREATE_INT_CLASS(int64, Int64, INT64);

    int32_class.add_simple_function("byteswap", [](DabValue self) {
        auto     value     = self.data.num_int32;
        auto     new_value = byteswap(value);
        DabValue ret(CLASS_INT32, new_value);
        return ret;
    });

    auto &boolean_class = get_class(CLASS_BOOLEAN);
    DAB_MEMBER_EQUALS_OPERATORS(boolean_class, CLASS_BOOLEAN, .data.boolean);

    auto &array_class = get_class(CLASS_ARRAY);
    array_class.add_simple_function("count", [](DabValue self) {
        assert(self.data.type == TYPE_ARRAY);
        return (uint64_t)self.array().size();
    });
    array_class.add_function("shift", [this](size_t n_args, size_t n_ret, void *blockaddr) {
        assert(blockaddr == 0);
        assert(n_args == 1);
        assert(n_ret == 1);
        auto self = stack.pop_value();
        assert(self.data.type == TYPE_ARRAY);
        auto &a = self.array();
        if (a.size() == 0)
        {
            stack.push_value(nullptr);
        }
        else
        {
            auto ret = a[0];
            a.erase(a.begin());
            stack.push_value(ret);
        }
    });
    array_class.add_function("insert", [this](size_t n_args, size_t n_ret, void *blockaddr) {
        assert(blockaddr == 0);
        assert(n_args == 2);
        assert(n_ret == 1);
        auto self = stack.pop_value();
        auto arg  = stack.pop_value();
        assert(self.data.type == TYPE_ARRAY);
        auto &a = self.array();
        a.push_back(arg);
        stack.push_value(nullptr);
    });
    array_class.add_function("[]", [this](size_t n_args, size_t n_ret, void *blockaddr) {
        assert(blockaddr == 0);
        assert(n_args == 2);
        assert(n_ret == 1);
        auto arg0 = stack.pop_value();
        auto arg1 = stack.pop_value();
        assert(arg0.data.type == TYPE_ARRAY);
        assert(arg1.data.type == TYPE_FIXNUM);
        auto &a = arg0.array();
        auto  n = arg1.data.fixnum;
        if (n < 0)
            n = a.size() + n;
        if (n < 0 || n >= (int64_t)a.size())
            stack.push_value(nullptr);
        else
            stack.push_value(a[n]);
    });
    array_class.add_function("[]=", [this](size_t n_args, size_t n_ret, void *blockaddr) {
        assert(blockaddr == 0);
        assert(n_args == 3);
        assert(n_ret == 1);
        auto arg0 = stack.pop_value();
        auto arg2 = stack.pop_value();
        auto arg1 = stack.pop_value();
        assert(arg0.data.type == TYPE_ARRAY);
        assert(arg1.data.type == TYPE_FIXNUM);
        auto &a = arg0.array();
        auto  n = arg1.data.fixnum;
        if (n < 0)
            n = a.size() + n;
        if (n < 0 || n >= (int64_t)a.size())
        {
            fprintf(stderr, "vm: index outside of array bounds.\n");
            exit(1);
        }
        else
        {
            a[n] = arg2;
            stack.push_value(nullptr);
        }
    });
    array_class.add_simple_function("join", [this](DabValue self) {
        std::string ret;
        auto &      a = self.array();
        for (size_t i = 0; i < a.size(); i++)
        {
            if (i)
                ret += ", ";
            instcall(a[i], "to_s", 0);
            auto val = stack.pop_value();
            ret += val.string();
        }
        return ret;
    });
    array_class.add_simple_function("to_s", [this](DabValue self) {
        instcall(self, "join", 0);
        auto inner = stack.pop_value();
        return std::string("[" + inner.string() + "]");
    });
    array_class.add_reg_function("+", [](DabValue self, std::vector<DabValue> args) {
        assert(args.size() == 1);
        auto arg = $VM->cast(args[0], CLASS_ARRAY);
        return $VM->merge_arrays(self, arg);
    });

    auto &method_class = get_class(CLASS_METHOD);
    method_class.add_simple_function(
        "to_s", [this](DabValue self) { return std::string("@method(" + self.string() + ")"); });

    auto &bytebuffer_class = get_class(CLASS_BYTEBUFFER);
    bytebuffer_class.add_static_function("new", [](size_t n_args, size_t n_ret, void *blockaddr) {
        assert(blockaddr == 0);
        assert(n_args == 2);
        assert(n_ret == 1);
        auto &stack = $VM->stack;
        auto  klass = stack.pop_value();
        assert(klass.data.type == TYPE_CLASS);

        auto instance = klass.create_instance();

        auto _size = $VM->cast(stack.pop_value(), CLASS_FIXNUM);
        auto size  = _size.data.fixnum;
        instance.bytebuffer().resize(size);
        stack.push_value(instance);
    });
    bytebuffer_class.add_function("[]", [this](size_t n_args, size_t n_ret, void *blockaddr) {
        assert(blockaddr == 0);
        assert(n_args == 2);
        assert(n_ret == 1);
        auto arg0 = stack.pop_value();
        auto arg1 = stack.pop_value();
        assert(arg0.data.type == TYPE_BYTEBUFFER);
        assert(arg1.data.type == TYPE_FIXNUM);
        auto &a = arg0.bytebuffer();
        auto  n = arg1.data.fixnum;
        if (n < 0)
            n = a.size() + n;
        if (n < 0 || n >= (int64_t)a.size())
            stack.push_value(nullptr);
        else
            stack.push_value(DabValue(CLASS_UINT8, a[n]));
    });
    bytebuffer_class.add_function("[]=", [this](size_t n_args, size_t n_ret, void *blockaddr) {
        assert(blockaddr == 0);
        assert(n_args == 3);
        assert(n_ret == 1);
        auto arg0 = stack.pop_value();
        auto arg2 = stack.pop_value();
        auto arg1 = stack.pop_value();
        assert(arg0.data.type == TYPE_BYTEBUFFER);
        assert(arg1.data.type == TYPE_FIXNUM);
        auto &a = arg0.bytebuffer();
        auto  n = arg1.data.fixnum;
        if (n < 0)
            n = a.size() + n;
        if (n < 0 || n >= (int64_t)a.size())
        {
            stack.push_value(nullptr);
        }
        else
        {
            a[n] = $VM->cast(arg2, CLASS_UINT8).data.num_uint8;
            stack.push_value(nullptr);
        }
    });
    bytebuffer_class.add_simple_function("to_s", [this](DabValue self) {
        std::string ret;
        auto &      a = self.bytebuffer();
        for (size_t i = 0; i < a.size(); i++)
        {
            if (i)
                ret += ", ";
            char string[32];
            sprintf(string, "%d", (int)a[i]);
            ret += string;
        }
        return "[" + ret + "]";
    });
}
