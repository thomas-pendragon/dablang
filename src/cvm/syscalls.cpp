#include "cvm.h"

#include "../cshared/opcodes_syscalls.h"

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

void DabVM::kernel_print(dab_register_t out_reg, std::vector<dab_register_t> reglist)
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
        arg.print(options.output);
        fflush(options.output);
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
    case KERNEL_BYTESWAP32:
    {
        kernel_byteswap32(out_reg, reglist);
        break;
    }
    default:
        fprintf(stderr, "VM error: Unknown kernel call <%d>.\n", (int)call);
        exit(1);
        break;
    }
}
