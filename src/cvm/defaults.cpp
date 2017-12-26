#include "cvm.h"

#ifndef DAB_PLATFORM_WINDOWS
#include <dlfcn.h>
#endif

#define STR2(s) #s
#define STR(s) STR2(s)

#ifdef __linux__
#define DAB_LIBC_NAME "libc.so.6" // LINUX
#else
#define DAB_LIBC_NAME "libc.dylib" // APPLE
#endif

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

dab_function_reg_t import_external_function(void *symbol, const DabFunctionReflection &reflection)
{
    return [symbol, &reflection](DabValue, std::vector<DabValue> args) {
        const auto &arg_klasses = reflection.arg_klasses;
        const auto  ret_klass   = reflection.ret_klass;

        assert(args.size() == arg_klasses.size());

        if (false)
        {
        }
#include "ffi_signatures.h"
        else
        {
            fprintf(stderr, "vm: unsupported signature\n");
            exit(1);
        }
    };
}

void DabVM::define_defaults()
{
    fprintf(stderr, "vm: define defaults\n");

    define_default_classes();

    fprintf(stderr, "vm: define default functions\n");

    auto make_import_function = [this](const char *name) {
        return [this, name](DabValue, std::vector<DabValue> args) {
#ifndef DAB_PLATFORM_WINDOWS
            assert(args.size() <= 2);

            std::string libc_name;

            if (args.size() == 2)
            {
                auto _libc_name = args[1];
                libc_name       = _libc_name.string();
            }
            auto method = args[0];
            assert(method.class_index() == CLASS_METHOD);
            auto method_name = method.string();
            if (args.size() == 1)
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
            if (options.verbose)
            {
                fprintf(stderr, "vm: dlopen handle: %p\n", handle);
            }

            auto symbol = dlsym(handle, libc_name.c_str());
            if (!symbol)
            {
                fprintf(stderr, "vm: dlsym error: %s", dlerror());
                exit(1);
            }
            if (options.verbose)
            {
                fprintf(stderr, "vm: dlsym handle: %p\n", symbol);
            }

            auto func_index = get_or_create_symbol_index(method_name);

            auto &function     = functions[func_index];
            function.regular   = false;
            function.address   = -1;
            function.extra_reg = import_external_function(symbol, function.reflection);

            return DabValue(nullptr);
#else
            (void)args;
            throw DabRuntimeError("function import not supported on windows yet");
            return DabValue(nullptr);
#endif
        };
    };

    {
        DabFunction fun;
        fun.name      = "__import_libc";
        fun.regular   = false;
        fun.extra_reg = make_import_function(DAB_LIBC_NAME);

        auto func_index = get_or_create_symbol_index("__import_libc");

        functions[func_index] = fun;
    }

    {
        DabFunction fun;
        fun.name      = "__import_sdl";
        fun.regular   = false;
        fun.extra_reg = make_import_function("/usr/local/lib/libSDL2.dylib");

        auto func_index = get_or_create_symbol_index("__import_sdl");

        functions[func_index] = fun;
    }

    {
        DabFunction fun;
        fun.name      = "__import_pq";
        fun.regular   = false;
        fun.extra_reg = make_import_function("/usr/local/lib/libpq.dylib");

        auto func_index = get_or_create_symbol_index("__import_pq");

        functions[func_index] = fun;
    }

    {
        DabFunction fun;
        fun.name      = "||";
        fun.regular   = false;
        fun.extra_reg = [this](DabValue, std::vector<DabValue> args) {
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
        fun.extra_reg = [this](DabValue, std::vector<DabValue> args) {
            assert(args.size() == 2);
            auto arg0 = args[0];
            auto arg1 = args[1];
            return arg0.truthy() ? arg1 : arg0;
        };

        auto func_index = get_or_create_symbol_index("&&");

        functions[func_index] = fun;
    }
}
