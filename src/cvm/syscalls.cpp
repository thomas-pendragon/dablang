#include "cvm.h"

#include "../cshared/opcodes_syscalls.h"

#ifndef DAB_PLATFORM_WINDOWS
#include <dlfcn.h>
#endif

#ifdef __linux__
#define DAB_LIBC_NAME "libc.so.6" // LINUX
#else
#define DAB_LIBC_NAME "libc.dylib" // APPLE
#endif

static int32_t byteswap(int32_t value)
{
    return ((value >> 24) & 0x000000FF) | ((value << 8) & 0x00FF0000) |
           ((value >> 8) & 0x0000FF00) | ((value << 24) & 0xFF000000);
}

void DabVM::kernel_byteswap32(dab_register_t out_reg, std::vector<dab_register_t> reglist)
{
    assert(reglist.size() == 1);
    DabValue arg       = register_get(reglist[0]);
    auto     value     = arg.data.num_int32;
    auto     new_value = byteswap(value);
    DabValue ret(CLASS_INT32, new_value);
    register_set(out_reg, ret);
}

dab_function_reg_t import_external_function(void *symbol, const DabFunctionReflection &reflection)
{
    return [symbol, &reflection](DabValue, std::vector<DabValue> args)
    {
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

void DabVM::kernel_dlimport(dab_register_t out_reg, std::vector<dab_register_t> reglist)
{
    assert(reglist.size() >= 2 && reglist.size() <= 3);
    DabValue path        = register_get(reglist[0]);
    DabValue method      = register_get(reglist[1]);
    auto     method_name = method.string();
    assert(method.class_index() == CLASS_METHOD);
    DabValue import_name = nullptr;
    if (reglist.size() == 3)
    {
        import_name = register_get(reglist[2]);
    }
    else
    {
        import_name = method.string();
    }

    auto name_ = path.string();

    if (name_ == "$LIBC")
    {
        name_ = DAB_LIBC_NAME;
    }

    auto name      = name_.c_str();
    auto libc_name = import_name.string();

#ifndef DAB_PLATFORM_WINDOWS
    fprintf(stderr, "vm: readjust '%s' to libc function '%s'\n", method_name.c_str(),
            libc_name.c_str());

    auto handle = dlopen(name, RTLD_LAZY);
    if (!handle)
    {
        fprintf(stderr, "vm: dlopen error: %s", dlerror());
        exit(1);
    }
    if ($VM->options.verbose)
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

    auto &function    = functions[func_index];
    function.regular  = false;
    function.dlimport = true;
    // function.address   = -1;
    function.extra_reg = import_external_function(symbol, function.reflection);

#else
    (void)args;
    if (true)
    {
        throw DabRuntimeError("function import not supported on windows yet");
    }
#endif

    register_set(out_reg, nullptr);
}

void DabVM::kernel_print(dab_register_t out_reg, std::vector<dab_register_t> reglist,
                         bool use_stderr)
{
    assert(reglist.size() == 1);
    DabValue arg = register_get(reglist[0]);

    arg = cinstcall(arg, "to_s");

    if (options.verbose)
    {
        fprintf(stderr, "[ ");
        arg.print(stderr);
        fprintf(stderr, " ]\n");
    }
    if (!options.coverage_testing && options.extract_part != "dumpvm")
    {
        auto output = use_stderr ? stderr : options.output;
        arg.print(output);
        fflush(output);
    }

    if (!options.autorelease)
    {
        arg.release();
    }

    register_set(out_reg, nullptr);
}

void DabVM::kernelcall(dab_register_t out_reg, int call, std::vector<dab_register_t> reglist)
{
    switch (call)
    {
    case KERNEL_PRINT:
    {
        kernel_print(out_reg, reglist);
        break;
    }
    case KERNEL_WARN:
    {
        kernel_print(out_reg, reglist, true);
        break;
    }
    case KERNEL_EXIT:
    {
        DabValue value;

        assert(reglist.size() == 1);
        value = register_get(reglist[0]);

        exit((int)value.data.fixnum);
        break;
    }
    case KERNEL_USECOUNT:
    {
        DabValue value;

        assert(reglist.size() == 1);
        value = register_get(reglist[0]);

        auto dab_value = uint64_t(value.use_count());

        register_set(out_reg, dab_value);
        break;
    }
    case KERNEL_TO_SYM:
    {
        auto string_ob = cast(register_get(reglist[0]), CLASS_STRING);
        auto string    = string_ob.string();

        auto symbol_index = get_or_create_symbol_index(string);

        DabValue value(CLASS_FIXNUM, (uint64_t)symbol_index);

        register_set(out_reg, value);
        break;
    }
    case KERNEL_FETCH_INT32:
    {
        assert(reglist.size() == 1);
        auto self = register_get(reglist[0]);

        auto     ptr   = self.data.intptr;
        auto     iptr  = (int32_t *)ptr;
        auto     value = *iptr;
        DabValue ret(CLASS_INT32, value);

        register_set(out_reg, ret);
        break;
    }
    case KERNEL_DEFINE_METHOD:
    {
        kernel_define_method(out_reg, reglist);
        break;
    }
    case KERNEL_DEFINE_CLASS:
    {
        kernel_define_class(out_reg, reglist);
        break;
    }
    case KERNEL_BYTESWAP32:
    {
        kernel_byteswap32(out_reg, reglist);
        break;
    }
    case KERNEL_DLIMPORT:
    {
        kernel_dlimport(out_reg, reglist);
        break;
    }
    default:
        fprintf(stderr, "VM error: Unknown kernel call <%d>.\n", (int)call);
        exit(1);
        break;
    }
}
