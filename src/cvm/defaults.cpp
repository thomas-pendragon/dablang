#include "cvm.h"
#include <dlfcn.h>

#define STR2(s) #s
#define STR(s) STR2(s)

#ifdef __linux__
#define DAB_LIBC_NAME "libc.so.6" // LINUX
#else
#define DAB_LIBC_NAME "libc.dylib" // APPLE
#endif

#define DAB_DEFINE_BASE_OP(op)                                                                     \
    assert(blockaddr == 0);                                                                        \
    assert(n_args == 2);                                                                           \
    assert(n_ret == 1);                                                                            \
    auto arg1 = stack.pop_value();                                                                 \
    auto arg0 = stack.pop_value();                                                                 \
    if (arg0.data.type != arg1.data.type)                                                          \
    {                                                                                              \
        assert(false && "mismtached types for operator " STR(op));                                 \
    }                                                                                              \
    if (arg0.data.type == TYPE_FIXNUM)                                                             \
    {                                                                                              \
        stack.push((uint64_t)(arg0.data.fixnum op arg1.data.fixnum));                              \
        return;                                                                                    \
    }                                                                                              \
    if (arg0.data.type == TYPE_UINT8)                                                              \
    {                                                                                              \
        uint8_t num_value = arg0.data.num_uint8 op arg1.data.num_uint8;                            \
                                                                                                   \
        DabValue value(CLASS_UINT8, num_value);                                                    \
                                                                                                   \
        stack.push_value(value);                                                                   \
        return;                                                                                    \
    }                                                                                              \
    if (arg0.data.type == TYPE_UINT64)                                                             \
    {                                                                                              \
        uint64_t num_value = arg0.data.num_uint64 op arg1.data.num_uint64;                         \
                                                                                                   \
        DabValue value(CLASS_UINT64, num_value);                                                   \
                                                                                                   \
        stack.push_value(value);                                                                   \
        return;                                                                                    \
    }

#define DAB_DEFINE_OP_STR(op)                                                                      \
    {                                                                                              \
        DabFunction fun;                                                                           \
        fun.name    = STR(op);                                                                     \
        fun.regular = false;                                                                       \
        fun.extra   = [this](size_t n_args, size_t n_ret, void *blockaddr) {                       \
            DAB_DEFINE_BASE_OP(op);                                                                \
            if (arg0.data.type == TYPE_ARRAY && arg1.data.type == TYPE_ARRAY)                      \
            {                                                                                      \
                stack.push(merge_arrays(arg0, arg1));                                              \
                return;                                                                            \
            }                                                                                      \
            else if (arg0.data.type == TYPE_STRING)                                                \
            {                                                                                      \
                stack.push(arg0.data.string op arg1.data.string);                                  \
                return;                                                                            \
            }                                                                                      \
            assert(false && "unknown types for operator " STR(op));                                \
        };                                                                                         \
        functions[STR(op)] = fun;                                                                  \
    }

#define DAB_DEFINE_OP(op)                                                                          \
    {                                                                                              \
        DabFunction fun;                                                                           \
        fun.name    = STR(op);                                                                     \
        fun.regular = false;                                                                       \
        fun.extra   = [this](size_t n_args, size_t n_ret, void *blockaddr) {                       \
            DAB_DEFINE_BASE_OP(op);                                                                \
            assert(false && "unknown types for operator " STR(op));                                \
        };                                                                                         \
        functions[STR(op)] = fun;                                                                  \
    }

#define DAB_DEFINE_OP_BOOL(op)                                                                     \
    {                                                                                              \
        DabFunction fun;                                                                           \
        fun.name    = STR(op);                                                                     \
        fun.regular = false;                                                                       \
        fun.extra   = [this](size_t n_args, size_t n_ret, void *blockaddr) {                       \
            assert(blockaddr == 0);                                                                \
            /*dump();*/                                                                            \
            assert(n_args == 2);                                                                   \
            assert(n_ret == 1);                                                                    \
            auto arg1       = stack.pop_value();                                                   \
            auto arg0       = stack.pop_value();                                                   \
            bool test       = false;                                                               \
            auto arg0_class = arg0.class_index();                                                  \
            auto arg1_class = arg1.class_index();                                                  \
            if (arg0_class == CLASS_UINT8 || arg0_class == CLASS_LITERALFIXNUM ||                  \
                arg0_class == CLASS_FIXNUM || arg0_class == CLASS_INT32)                           \
            {                                                                                      \
                if (arg1_class != CLASS_STRING)                                                    \
                {                                                                                  \
                    arg1 = $VM->cast(arg1, arg0_class);                                            \
                }                                                                                  \
            }                                                                                      \
                                                                                                   \
            if (arg0.data.type != arg1.data.type)                                                  \
            {                                                                                      \
                test = true op false;                                                              \
            }                                                                                      \
            else if (arg0.data.type == TYPE_FIXNUM)                                                \
            {                                                                                      \
                test = arg0.data.fixnum op arg1.data.fixnum;                                       \
            }                                                                                      \
            else if (arg0.data.type == TYPE_UINT8)                                                 \
            {                                                                                      \
                test = arg0.data.num_uint8 op arg1.data.num_uint8;                                 \
            }                                                                                      \
            else if (arg0.data.type == TYPE_INT32)                                                 \
            {                                                                                      \
                test = arg0.data.num_int32 op arg1.data.num_int32;                                 \
            }                                                                                      \
            else if (arg0.data.type == TYPE_STRING)                                                \
            {                                                                                      \
                test = arg0.data.string op arg1.data.string;                                       \
            }                                                                                      \
            else if (arg0.data.type == TYPE_CLASS)                                                 \
            {                                                                                      \
                test = arg0.data.fixnum op arg1.data.fixnum;                                       \
                fprintf(stderr, "compare classes: %d %d %s -> %s\n", (int)arg0.data.fixnum,        \
                        (int)arg1.data.fixnum, STR(op), test ? "yes" : "no");                      \
            }                                                                                      \
            else                                                                                   \
            {                                                                                      \
                fprintf(stderr, "vm: unknown type to compare\n");                                  \
            }                                                                                      \
            stack.push(test);                                                                      \
        };                                                                                         \
        functions[STR(op)] = fun;                                                                  \
    }

DabValue DabVM::merge_arrays(const DabValue &arg0, const DabValue &arg1)
{
    auto &   a0          = arg0.array();
    auto &   a1          = arg1.array();
    DabValue array_class = classes[CLASS_ARRAY];
    DabValue value       = array_class.create_instance();
    auto &   array       = value.array();
    array.resize(a0.size() + a1.size());
    fprintf(stderr, "vm: merge %d and %d items into new %d-sized array\n", (int)a0.size(),
            (int)a1.size(), (int)array.size());
    size_t i = 0;
    for (auto &item : a0)
    {
        array[i++] = item;
    }
    for (auto &item : a1)
    {
        array[i++] = item;
    }
    return value;
}

dab_function_t import_external_function(void *symbol, const DabFunctionReflection &reflection,
                                        Stack &stack)
{
    return [symbol, &reflection, &stack](size_t n_args, size_t n_ret, void *blockaddr) {
        const auto &arg_klasses = reflection.arg_klasses;
        const auto  ret_klass   = reflection.ret_klass;

        assert(blockaddr == 0);
        assert(n_args == arg_klasses.size());
        assert(n_ret == 1);

        if (arg_klasses.size() == 1 && arg_klasses[0] == CLASS_INT32 && ret_klass == CLASS_INT32)
        {
            typedef int (*int_fun)(int);

            auto int_symbol = (int_fun)symbol;

            auto value = stack.pop_value();
            if (value.class_index() == CLASS_LITERALFIXNUM)
            {
                value = $VM->cast(value, CLASS_INT32);
            }
            assert(value.class_index() == CLASS_INT32);

            auto value_data = value.data.num_int32;

            auto return_value = (*int_symbol)(value_data);

            stack.push_value(DabValue(CLASS_INT32, return_value));
        }
        else if (arg_klasses.size() == 0 && ret_klass == CLASS_UINT64)
        {
            typedef uint64_t (*int_fun)();

            auto int_symbol = (int_fun)symbol;

            auto return_value = (*int_symbol)();

            stack.push_value(DabValue(CLASS_UINT64, return_value));
        }
        else if (arg_klasses.size() == 1 && arg_klasses[0] == CLASS_UINT32 &&
                 ret_klass == CLASS_INT32)
        {
            typedef int (*int_fun)(uint32_t);

            auto int_symbol = (int_fun)symbol;

            auto value = stack.pop_value();
            if (value.class_index() == CLASS_LITERALFIXNUM)
            {
                value = $VM->cast(value, CLASS_UINT32);
            }
            assert(value.class_index() == CLASS_UINT32);

            auto value_data = value.data.num_uint32;

            auto return_value = (*int_symbol)(value_data);

            stack.push_value(DabValue(CLASS_INT32, return_value));
        }
        else if (arg_klasses.size() == 1 && arg_klasses[0] == CLASS_INTPTR &&
                 ret_klass == CLASS_INT32)
        {
            typedef int (*int_fun)(void *);

            auto int_symbol = (int_fun)symbol;

            auto value = $VM->cast(stack.pop_value(), CLASS_INTPTR);
            assert(value.class_index() == CLASS_INTPTR);

            auto value_data = value.data.intptr;

            auto return_value = (*int_symbol)(value_data);
            if ($VM->verbose)
            {
                fprintf(stderr, "vm: ffi int(void*): (%p) -> %d\n", value_data, return_value);
            }

            stack.push_value(DabValue(CLASS_INT32, return_value));
        }
        else if (arg_klasses.size() == 1 && arg_klasses[0] == CLASS_INTPTR &&
                 ret_klass == CLASS_NILCLASS)
        {
            typedef void (*int_fun)(void *);

            auto int_symbol = (int_fun)symbol;

            auto value = $VM->cast(stack.pop_value(), CLASS_INTPTR);
            assert(value.class_index() == CLASS_INTPTR);

            auto value_data = value.data.intptr;

            (*int_symbol)(value_data);
            if ($VM->verbose)
            {
                fprintf(stderr, "vm: ffi void(void*): (%p)\n", value_data);
            }

            stack.push_value(DabValue(nullptr));
        }
        else if (arg_klasses.size() == 1 && arg_klasses[0] == CLASS_UINT32 &&
                 ret_klass == CLASS_NILCLASS)
        {
            typedef void (*int_fun)(uint32_t);

            auto int_symbol = (int_fun)symbol;

            auto value = stack.pop_value();
            if (value.class_index() == CLASS_LITERALFIXNUM)
            {
                value = $VM->cast(value, CLASS_UINT32);
            }
            assert(value.class_index() == CLASS_UINT32);

            auto value_data = value.data.num_uint32;

            (*int_symbol)(value_data);

            stack.push_value(DabValue(nullptr));
        }
        else if (arg_klasses.size() == 1 && arg_klasses[0] == CLASS_STRING &&
                 ret_klass == CLASS_UINT64)
        {
            typedef uint64_t (*int_fun)(const char *);

            auto int_symbol = (int_fun)symbol;

            auto value = stack.pop_value();
            assert(value.class_index() == CLASS_STRING ||
                   value.class_index() == CLASS_LITERALSTRING);

            auto value_data = value.data.string.c_str();

            auto return_value = (*int_symbol)(value_data);

            stack.push_value(DabValue(CLASS_UINT64, return_value));
        }
        else if (arg_klasses.size() == 3 && arg_klasses[0] == CLASS_INTPTR &&
                 arg_klasses[1] == CLASS_INT32 && arg_klasses[2] == CLASS_UINT32 &&
                 ret_klass == CLASS_INTPTR)
        {
            typedef void *(*int_fun)(void *, int, uint32_t);

            auto int_symbol = (int_fun)symbol;

            auto value2 = $VM->cast(stack.pop_value(), CLASS_UINT32);
            auto value1 = $VM->cast(stack.pop_value(), CLASS_INT32);

            auto value = stack.pop_value();
            assert(value.class_index() == CLASS_INTPTR);

            auto value_data  = value.data.intptr;
            auto value1_data = value.data.num_int32;
            auto value2_data = value.data.num_uint32;

            auto return_value = (*int_symbol)(value_data, value1_data, value2_data);

            stack.push_value(DabValue(CLASS_INTPTR, return_value));
        }
        else if (arg_klasses.size() == 5 && arg_klasses[0] == CLASS_INTPTR &&
                 arg_klasses[1] == CLASS_UINT8 && arg_klasses[2] == CLASS_UINT8 &&
                 arg_klasses[3] == CLASS_UINT8 && arg_klasses[4] == CLASS_UINT8 &&
                 ret_klass == CLASS_INT32)
        {
            typedef int (*int_fun)(void *, uint8_t, uint8_t, uint8_t, uint8_t);

            auto int_symbol = (int_fun)symbol;

            auto value4 = $VM->cast(stack.pop_value(), CLASS_UINT8);
            auto value3 = $VM->cast(stack.pop_value(), CLASS_UINT8);
            auto value2 = $VM->cast(stack.pop_value(), CLASS_UINT8);
            auto value1 = $VM->cast(stack.pop_value(), CLASS_UINT8);
            auto value0 = $VM->cast(stack.pop_value(), CLASS_INTPTR);

            auto value0_data = value0.data.intptr;
            auto value1_data = value1.data.num_uint8;
            auto value2_data = value2.data.num_uint8;
            auto value3_data = value3.data.num_uint8;
            auto value4_data = value4.data.num_uint8;

            auto return_value =
                (*int_symbol)(value0_data, value1_data, value2_data, value3_data, value4_data);

            stack.push_value(DabValue(CLASS_INT32, return_value));
        }
        else if (arg_klasses.size() == 5 && arg_klasses[0] == CLASS_INTPTR &&
                 arg_klasses[1] == CLASS_INT32 && arg_klasses[2] == CLASS_INT32 &&
                 arg_klasses[3] == CLASS_INT32 && arg_klasses[4] == CLASS_INT32 &&
                 ret_klass == CLASS_INT32)
        {
            typedef int (*int_fun)(void *, int, int, int, int);

            auto int_symbol = (int_fun)symbol;

            auto value4 = $VM->cast(stack.pop_value(), CLASS_INT32);
            auto value3 = $VM->cast(stack.pop_value(), CLASS_INT32);
            auto value2 = $VM->cast(stack.pop_value(), CLASS_INT32);
            auto value1 = $VM->cast(stack.pop_value(), CLASS_INT32);
            auto value0 = $VM->cast(stack.pop_value(), CLASS_INTPTR);

            auto value0_data = value0.data.intptr;
            auto value1_data = value1.data.num_int32;
            auto value2_data = value2.data.num_int32;
            auto value3_data = value3.data.num_int32;
            auto value4_data = value4.data.num_int32;

            auto return_value =
                (*int_symbol)(value0_data, value1_data, value2_data, value3_data, value4_data);

            stack.push_value(DabValue(CLASS_INT32, return_value));
        }
        else if (arg_klasses.size() == 6 && arg_klasses[0] == CLASS_STRING &&
                 arg_klasses[1] == CLASS_INT32 && arg_klasses[2] == CLASS_INT32 &&
                 arg_klasses[3] == CLASS_INT32 && arg_klasses[4] == CLASS_INT32 &&
                 arg_klasses[5] == CLASS_UINT32 && ret_klass == CLASS_INTPTR)
        {
            typedef void *(*int_fun)(const char *, int, int, int, int, uint32_t);

            auto int_symbol = (int_fun)symbol;

            auto value5 = $VM->cast(stack.pop_value(), CLASS_UINT32);
            auto value4 = $VM->cast(stack.pop_value(), CLASS_INT32);
            auto value3 = $VM->cast(stack.pop_value(), CLASS_INT32);
            auto value2 = $VM->cast(stack.pop_value(), CLASS_INT32);
            auto value1 = $VM->cast(stack.pop_value(), CLASS_INT32);

            auto value0 = stack.pop_value();
            assert(value0.class_index() == CLASS_STRING ||
                   value0.class_index() == CLASS_LITERALSTRING);

            auto value0_data = value0.data.string.c_str();
            auto value1_data = value1.data.num_int32;
            auto value2_data = value2.data.num_int32;
            auto value3_data = value3.data.num_int32;
            auto value4_data = value4.data.num_int32;
            auto value5_data = value5.data.num_uint32;

            auto return_value = (*int_symbol)(value0_data, value1_data, value2_data, value3_data,
                                              value4_data, value5_data);

            fprintf(stderr,
                    "vm: ffi void*(const char*, int, int, int, int, uint32_t): (%s, %d, %d, %d, "
                    "%d, %d) -> %p\n",
                    value0_data, (int)value1_data, (int)value2_data, (int)value3_data,
                    (int)value4_data, (int)value5_data, return_value);

            stack.push_value(DabValue(CLASS_INTPTR, return_value));
        }
        else
        {
            fprintf(stderr, "vm: unsupported signature\n");
            exit(1);
        }
    };
}

void DabVM::define_defaults()
{
    define_default_classes();

    DAB_DEFINE_OP_STR(+);
    DAB_DEFINE_OP(-);
    DAB_DEFINE_OP(*);
    DAB_DEFINE_OP(/);
    DAB_DEFINE_OP(%);
    DAB_DEFINE_OP(|);
    DAB_DEFINE_OP_BOOL(==);
    DAB_DEFINE_OP_BOOL(!=);
    DAB_DEFINE_OP_BOOL(>=);
    DAB_DEFINE_OP_BOOL(>);
    DAB_DEFINE_OP_BOOL(<=);
    DAB_DEFINE_OP_BOOL(<);

    auto make_import_function = [this](const char *name) {
        return [this, name](size_t n_args, size_t n_ret, void *blockaddr) {
            assert(blockaddr == 0);
            assert(n_args == 2 || n_args == 1);
            assert(n_ret == 1);

            std::string libc_name;

            if (n_args == 2)
            {
                auto _libc_name = stack.pop_value();
                assert(_libc_name.class_index() == CLASS_STRING ||
                       _libc_name.class_index() == CLASS_LITERALSTRING);
                libc_name = _libc_name.data.string;
            }
            auto method = stack.pop_value();
            assert(method.class_index() == CLASS_METHOD);
            auto method_name = method.data.string;
            if (n_args == 1)
            {
                libc_name = method_name;
            }

            fprintf(stderr, "vm: readjust '%s' to libc function '%s'\n", method_name.c_str(),
                    libc_name.c_str());

            auto handle = dlopen(name, RTLD_LAZY);
            if (!handle)
            {
                fprintf(stderr, "vm: dlopen error: %s", dlerror());
                exit(1);
            }
            fprintf(stderr, "vm: dlopen handle: %p\n", handle);

            auto symbol = dlsym(handle, libc_name.c_str());
            if (!symbol)
            {
                fprintf(stderr, "vm: dlsym error: %s", dlerror());
                exit(1);
            }
            fprintf(stderr, "vm: dlsym handle: %p\n", symbol);

            auto &function   = functions[method_name];
            function.regular = false;
            function.address = -1;
            function.extra   = import_external_function(symbol, function.reflection, this->stack);

            stack.push_value(DabValue(nullptr));
        };
    };

    {
        DabFunction fun;
        fun.name                   = "__import_libc";
        fun.regular                = false;
        fun.extra                  = make_import_function(DAB_LIBC_NAME);
        functions["__import_libc"] = fun;
    }

    {
        DabFunction fun;
        fun.name                  = "__import_sdl";
        fun.regular               = false;
        fun.extra                 = make_import_function("/usr/local/lib/libSDL2.dylib");
        functions["__import_sdl"] = fun;
    }

    {
        DabFunction fun;
        fun.name    = "is";
        fun.regular = false;
        fun.extra   = [this](size_t n_args, size_t n_ret, void *blockaddr) {
            assert(blockaddr == 0);
            assert(n_args == 2);
            assert(n_ret == 1);
            auto arg1 = stack.pop_value();
            auto arg0 = stack.pop_value();
            stack.push_value(arg0.is_a(arg1.get_class()));
        };
        functions["is"] = fun;
    }

    {
        DabFunction fun;
        fun.name    = "||";
        fun.regular = false;
        fun.extra   = [this](size_t n_args, size_t n_ret, void *blockaddr) {
            assert(blockaddr == 0);
            // dump();
            assert(n_args == 2);
            assert(n_ret == 1);
            auto arg1 = stack.pop_value();
            auto arg0 = stack.pop_value();
            stack.push_value(arg0.truthy() ? arg0 : arg1);
        };
        functions["||"] = fun;
    }

    {
        DabFunction fun;
        fun.name    = "&&";
        fun.regular = false;
        fun.extra   = [this](size_t n_args, size_t n_ret, void *blockaddr) {
            assert(blockaddr == 0);
            // dump();
            assert(n_args == 2);
            assert(n_ret == 1);
            auto arg1 = stack.pop_value();
            auto arg0 = stack.pop_value();
            stack.push_value(arg0.truthy() ? arg1 : arg0);
        };
        functions["&&"] = fun;
    }
}
