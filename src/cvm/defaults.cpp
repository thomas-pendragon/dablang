#include "cvm.h"

#define STR2(s) #s
#define STR(s) STR2(s)
#define DAB_DEFINE_OP_STR(op)                                                                      \
    {                                                                                              \
        DabFunction fun;                                                                           \
        fun.name    = STR(op);                                                                     \
        fun.regular = false;                                                                       \
        fun.extra   = [this]() {                                                                   \
            dump();                                                                                \
            auto     arg1 = stack.pop_value();                                                     \
            auto     arg0 = stack.pop_value();                                                     \
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
            auto     arg1 = stack.pop_value();                                                     \
            auto     arg0 = stack.pop_value();                                                     \
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
            auto arg1 = stack.pop_value();                                                         \
            auto arg0 = stack.pop_value();                                                         \
            bool test = arg0.fixnum op arg1.fixnum;                                                \
            stack_push(test);                                                                      \
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

    add_c_function("String::upcase", [this]() {
        auto arg0 = stack.pop_value();
        assert(arg0.type == TYPE_STRING);
        auto &s = arg0.string;
        std::transform(s.begin(), s.end(), s.begin(), ::toupper);
        stack.push(arg0);
    });

    add_c_function("String::class", [this]() {
        stack.pop_value();
        stack_push(std::string("LiteralString"));
    });

    add_c_function("Fixnum::class", [this]() {
        stack.pop_value();
        stack_push(std::string("LiteralFixnum"));
    });

    add_c_function("Boolean::class", [this]() {
        stack.pop_value();
        stack_push(std::string("LiteralBoolean"));
    });

    add_c_function("MyObject::new", [this]() {
        stack.pop_value();
        stack_push(std::string("#MyObject"));
    });
}
