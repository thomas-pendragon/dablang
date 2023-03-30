#include "cvm.h"

#define STR2(s) #s
#define STR(s) STR2(s)

#ifdef __linux__
#define DAB_LIBC_NAME "libc.so.6" // LINUX
#else
#define DAB_LIBC_NAME "libc.dylib" // APPLE
#endif

DabValue DabVM::merge_arrays(const DabValue &arg0, const DabValue &arg1)
{
    auto    &a0          = arg0.array();
    auto    &a1          = arg1.array();
    DabValue array_class = classes[CLASS_ARRAY];
    DabValue value       = array_class.create_instance();
    auto    &array       = value.array();
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
    fprintf(stderr, "vm: define defaults\n");

    define_default_classes();

    fprintf(stderr, "vm: define default functions\n");

//    {
//        DabFunction fun;
//        fun.name      = "__import_libc";
//        fun.regular   = false;
//        fun.extra_reg = make_import_function(DAB_LIBC_NAME);
//
//        auto func_index = get_or_create_symbol_index("__import_libc");
//
//        functions[func_index] = fun;
//    }
//

    {
        DabFunction fun;
        fun.name      = "||";
        fun.regular   = false;
        fun.extra_reg = [](DabValue, std::vector<DabValue> args)
        {
            assert(args.size() == 2);
            auto arg0 = args[0];
            auto arg1 = args[1];
            return arg0.truthy() ? arg0 : arg1;
        };

        auto func_index = get_or_create_symbol_index("||");

        functions[func_index] = fun;
    }

    {
        DabFunction fun;
        fun.name      = "&&";
        fun.regular   = false;
        fun.extra_reg = [](DabValue, std::vector<DabValue> args)
        {
            assert(args.size() == 2);
            auto arg0 = args[0];
            auto arg1 = args[1];
            return arg0.truthy() ? arg1 : arg0;
        };

        auto func_index = get_or_create_symbol_index("&&");

        functions[func_index] = fun;
    }
}
