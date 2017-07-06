#include "cvm.h"

#define STR2(s) #s
#define STR(s) STR2(s)

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
            auto arg1 = stack.pop_value();                                                         \
            auto arg0 = stack.pop_value();                                                         \
            bool test = false;                                                                     \
            if (arg0.data.type != arg1.data.type)                                                  \
            {                                                                                      \
                test = true op false;                                                              \
            }                                                                                      \
            else if (arg0.data.type == TYPE_FIXNUM)                                                \
            {                                                                                      \
                test = arg0.data.fixnum op arg1.data.fixnum;                                       \
            }                                                                                      \
            else if (arg0.data.type == TYPE_STRING)                                                \
            {                                                                                      \
                test = arg0.data.string op arg1.data.string;                                       \
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

void DabVM::define_defaults()
{
    define_default_classes();

    DAB_DEFINE_OP_STR(+);
    DAB_DEFINE_OP(-);
    DAB_DEFINE_OP(*);
    DAB_DEFINE_OP(/);
    DAB_DEFINE_OP(%);
    DAB_DEFINE_OP_BOOL(==);
    DAB_DEFINE_OP_BOOL(!=);
    DAB_DEFINE_OP_BOOL(>=);
    DAB_DEFINE_OP_BOOL(>);
    DAB_DEFINE_OP_BOOL(<=);
    DAB_DEFINE_OP_BOOL(<);

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
