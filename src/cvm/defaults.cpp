#include "cvm.h"

#define STR2(s) #s
#define STR(s) STR2(s)
#define DAB_DEFINE_OP_STR(op)                                                                      \
    {                                                                                              \
        DabFunction fun;                                                                           \
        fun.name    = STR(op);                                                                     \
        fun.regular = false;                                                                       \
        fun.extra   = [this](size_t n_args, size_t n_ret) {                                        \
            /*dump();*/                                                                            \
            assert(n_args == 2);                                                                   \
            assert(n_ret == 1);                                                                    \
            auto     arg1 = stack.pop_value();                                                     \
            auto     arg0 = stack.pop_value();                                                     \
            uint64_t num  = arg0.data.fixnum op arg1.data.fixnum;                                  \
            auto str      = arg0.data.string op arg1.data.string;                                  \
            if (arg0.data.type == TYPE_FIXNUM)                                                     \
                stack.push(num);                                                                   \
            else                                                                                   \
                stack.push(str);                                                                   \
        };                                                                                         \
        functions[STR(op)] = fun;                                                                  \
    }

#define DAB_DEFINE_OP(op)                                                                          \
    {                                                                                              \
        DabFunction fun;                                                                           \
        fun.name    = STR(op);                                                                     \
        fun.regular = false;                                                                       \
        fun.extra   = [this](size_t n_args, size_t n_ret) {                                        \
            /* dump();*/                                                                           \
            assert(n_args == 2);                                                                   \
            assert(n_ret == 1);                                                                    \
            auto     arg1 = stack.pop_value();                                                     \
            auto     arg0 = stack.pop_value();                                                     \
            uint64_t num  = arg0.data.fixnum op arg1.data.fixnum;                                  \
            stack.push(num);                                                                       \
        };                                                                                         \
        functions[STR(op)] = fun;                                                                  \
    }

#define DAB_DEFINE_OP_BOOL(op)                                                                     \
    {                                                                                              \
        DabFunction fun;                                                                           \
        fun.name    = STR(op);                                                                     \
        fun.regular = false;                                                                       \
        fun.extra   = [this](size_t n_args, size_t n_ret) {                                        \
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

    {
        DabFunction fun;
        fun.name    = "is";
        fun.regular = false;
        fun.extra   = [this](size_t n_args, size_t n_ret) {
            assert(n_args == 2);
            assert(n_ret == 1);
            auto arg1 = stack.pop_value();
            auto arg0 = stack.pop_value();
            stack.push_value(arg0.is_a(*this, arg1.get_class(*this)));
        };
        functions["is"] = fun;
    }

    {
        DabFunction fun;
        fun.name    = "||";
        fun.regular = false;
        fun.extra   = [this](size_t n_args, size_t n_ret) {
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
        fun.extra   = [this](size_t n_args, size_t n_ret) {
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
