#include "cvm.h"
#include <dlfcn.h>

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

dab_function_t import_external_function(void *symbol, const DabFunctionReflection &reflection,
                                        Stack &stack)
{
    return [symbol, &reflection, &stack](size_t n_args, size_t n_ret, void *blockaddr) {
        const auto &arg_klasses = reflection.arg_klasses;
        const auto  ret_klass   = reflection.ret_klass;

        assert(blockaddr == 0);
        assert(n_args == arg_klasses.size());
        assert(n_ret == 1);

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
    define_default_classes();

    auto make_import_function = [this](const char *name) {
        return [this, name](size_t n_args, size_t n_ret, void *blockaddr) {
            assert(blockaddr == 0);
            assert(n_args == 2 || n_args == 1);
            assert(n_ret == 1);

            std::string libc_name;

            if (n_args == 2)
            {
                auto _libc_name = stack.pop_value();
                libc_name       = _libc_name.string();
            }
            auto method = stack.pop_value();
            assert(method.class_index() == CLASS_METHOD);
            auto method_name = method.string();
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
            if (verbose)
            {
                fprintf(stderr, "vm: dlopen handle: %p\n", handle);
            }

            auto symbol = dlsym(handle, libc_name.c_str());
            if (!symbol)
            {
                fprintf(stderr, "vm: dlsym error: %s", dlerror());
                exit(1);
            }
            if (verbose)
            {
                fprintf(stderr, "vm: dlsym handle: %p\n", symbol);
            }

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
        fun.name                 = "__import_pq";
        fun.regular              = false;
        fun.extra                = make_import_function("/usr/local/lib/libpq.dylib");
        functions["__import_pq"] = fun;
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
