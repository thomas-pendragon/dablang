#include "cvm.h"

#include "../cshared/opcodes_syscalls.h"

#include <memory>
#include <new>

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
    if (!options.allow_unsafe_ffi)
    {
        throw DabRuntimeError(
            "unsafe FFI is disabled; use --allow-unsafe-ffi only for trusted local code");
    }

    assert(reglist.size() >= 2 && reglist.size() <= 3);
#ifdef DAB_PLATFORM_WINDOWS
    (void)out_reg;
    (void)reglist;
    throw DabRuntimeError("function import not supported on windows yet");
#else
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

    auto libc_name = import_name.string();

    fprintf(stderr, "vm: readjust '%s' to libc function '%s'\n", method_name.c_str(),
            libc_name.c_str());

    auto handle = dlopen(name_.c_str(), RTLD_LAZY);
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

    register_set(out_reg, nullptr);
#endif
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

static bool modern_return_supported_class(int64_t target)
{
    switch (target)
    {
    case CLASS_FIXNUM:
    case CLASS_UINT8:
    case CLASS_UINT16:
    case CLASS_UINT32:
    case CLASS_UINT64:
    case CLASS_INT8:
    case CLASS_INT16:
    case CLASS_INT32:
    case CLASS_INT64:
    case CLASS_STRING:
    case CLASS_BOOLEAN:
    case CLASS_NILCLASS:
    case CLASS_INTPTR:
    case CLASS_FLOAT:
        return true;
    default:
        return false;
    }
}

static bool modern_return_integer_bits(const DabValue &value, uint64_t &bits)
{
    // Signed-to-unsigned conversion sign-extends modulo 2^64 before narrowing.
    switch (value.data.type)
    {
    case TYPE_FIXNUM:
        bits = static_cast<uint64_t>(value.data.fixnum);
        return true;
    case TYPE_UINT8:
        bits = value.data.num_uint8;
        return true;
    case TYPE_UINT16:
        bits = value.data.num_uint16;
        return true;
    case TYPE_UINT32:
        bits = value.data.num_uint32;
        return true;
    case TYPE_UINT64:
        bits = value.data.num_uint64;
        return true;
    case TYPE_INT8:
        bits = static_cast<uint64_t>(value.data.num_int8);
        return true;
    case TYPE_INT16:
        bits = static_cast<uint64_t>(value.data.num_int16);
        return true;
    case TYPE_INT32:
        bits = static_cast<uint64_t>(value.data.num_int32);
        return true;
    case TYPE_INT64:
        bits = static_cast<uint64_t>(value.data.num_int64);
        return true;
    default:
        return false;
    }
}

static int64_t modern_return_signed(uint64_t bits, unsigned width)
{
    const auto mask = width == 64 ? UINT64_MAX : (uint64_t(1) << width) - 1;
    bits &= mask;
    // Both casts are in range, including INT64_MIN; no signed overflow or
    // implementation-defined unsigned-to-signed conversion is needed.
    if (bits & (uint64_t(1) << (width - 1)))
    {
        return -1 - static_cast<int64_t>((~bits) & mask);
    }
    return static_cast<int64_t>(bits);
}

static DabValue modern_return_normalize(const DabValue &value, dab_class_t target)
{
    if (value.nil())
    {
        return value;
    }
    uint64_t bits = 0;
    if (modern_return_integer_bits(value, bits))
    {
        switch (target)
        {
        case CLASS_FIXNUM:
        {
            DabValue result;
            result.data.type   = TYPE_FIXNUM;
            result.data.fixnum = modern_return_signed(bits, 64);
            return result;
        }
        case CLASS_UINT8:
            return DabValue(target, static_cast<uint8_t>(bits));
        case CLASS_UINT16:
            return DabValue(target, static_cast<uint16_t>(bits));
        case CLASS_UINT32:
            return DabValue(target, static_cast<uint32_t>(bits));
        case CLASS_UINT64:
            return DabValue(target, bits);
        case CLASS_INT8:
            return DabValue(target, static_cast<int8_t>(modern_return_signed(bits, 8)));
        case CLASS_INT16:
            return DabValue(target, static_cast<int16_t>(modern_return_signed(bits, 16)));
        case CLASS_INT32:
            return DabValue(target, static_cast<int32_t>(modern_return_signed(bits, 32)));
        case CLASS_INT64:
            return DabValue(target, modern_return_signed(bits, 64));
        default:
            break;
        }
    }
    const bool string =
        value.data.type == TYPE_LITERALSTRING || value.data.type == TYPE_DYNAMICSTRING;
    if ((target == CLASS_STRING && string) ||
        (target == CLASS_BOOLEAN && value.data.type == TYPE_BOOLEAN) ||
        (target == CLASS_INTPTR && value.data.type == TYPE_INTPTR) ||
        (target == CLASS_FLOAT && value.data.type == TYPE_FLOAT))
    {
        return value;
    }
    const auto actual = string                          ? "String"
                        : value.data.type == TYPE_BOX   ? "Box"
                        : value.data.type == TYPE_CLASS ? "Class"
                                                        : value.class_name();
    throw DabRuntimeError("Modern return expected " + $VM->get_class(target).name + ", got " +
                          actual);
}

static DabValue modern_to_string(const DabValue &value)
{
    if (value.data.type == TYPE_LITERALSTRING || value.data.type == TYPE_DYNAMICSTRING)
    {
        return value;
    }

    const char *text   = nullptr;
    size_t      length = 0;
    char        digits[21];
    uint64_t    bits = 0;
    if (value.data.type == TYPE_NIL)
    {
        text   = "nil";
        length = 3;
    }
    else if (value.data.type == TYPE_BOOLEAN)
    {
        text   = value.data.boolean ? "true" : "false";
        length = value.data.boolean ? 4 : 5;
    }
    else if (modern_return_integer_bits(value, bits))
    {
        bool negative = false;
        switch (value.data.type)
        {
        case TYPE_FIXNUM:
            negative = value.data.fixnum < 0;
            break;
        case TYPE_INT8:
            negative = value.data.num_int8 < 0;
            break;
        case TYPE_INT16:
            negative = value.data.num_int16 < 0;
            break;
        case TYPE_INT32:
            negative = value.data.num_int32 < 0;
            break;
        case TYPE_INT64:
            negative = value.data.num_int64 < 0;
            break;
        default:
            break;
        }
        // Unsigned magnitude handles INT64_MIN without negating a signed value.
        uint64_t magnitude = negative ? uint64_t(0) - bits : bits;
        char    *cursor    = digits + sizeof(digits);
        do
        {
            *--cursor = static_cast<char>('0' + magnitude % 10);
            magnitude /= 10;
        } while (magnitude);
        if (negative)
        {
            *--cursor = '-';
        }
        text   = cursor;
        length = static_cast<size_t>(digits + sizeof(digits) - cursor);
    }
    else
    {
        const auto actual = value.data.type == TYPE_BOX     ? "Box"
                            : value.data.type == TYPE_CLASS ? "Class"
                                                            : value.class_name();
        throw DabRuntimeError("Modern conversion to String does not support " + actual);
    }

    // Keep partial allocations owned locally until a complete value can be
    // published. This bypasses public methods and class/Ring override dispatch.
    std::unique_ptr<DabDynamicString> object(new DabDynamicString);
    object->klass = CLASS_DYNAMICSTRING;
    object->value.assign(text, length);
    std::unique_ptr<DabObjectProxy> proxy(new DabObjectProxy);
    proxy->object       = object.get();
    proxy->count_strong = 1;
    DabValue result;
    result.data.type   = TYPE_DYNAMICSTRING;
    result.data.object = proxy.release();
    object.release();
    return result;
}

void DabVM::kernelcall(dab_register_t out_reg, int call, std::vector<dab_register_t> reglist)
{
    switch (call)
    {
    case KERNEL_MODERN_TO_STRING:
    {
        if (reglist.size() != 1)
        {
            throw DabRuntimeError("internal Modern conversion to String expects 1 argument, got " +
                                  std::to_string(reglist.size()));
        }
        if (out_reg.nil())
        {
            throw DabRuntimeError(
                "internal Modern conversion to String requires a result register");
        }
        const auto reg = reglist[0];
        if (reg.nil() || reg.value() >= _registers.size() ||
            _registers[reg.value()].data.type == TYPE_INVALID)
        {
            throw DabRuntimeError(
                "internal Modern conversion to String received an invalid value register");
        }
        const auto value = register_get(reg);
        try
        {
            register_set(out_reg, modern_to_string(value));
        }
        catch (const std::bad_alloc &)
        {
            throw DabRuntimeError("Modern conversion to String failed: out of memory");
        }
        break;
    }
    case KERNEL_MODERN_RETURN_NORMALIZE:
    {
        if (reglist.size() != 2)
        {
            throw DabRuntimeError("internal Modern return normalization expects 2 arguments, got " +
                                  std::to_string(reglist.size()));
        }
        if (out_reg.nil())
        {
            throw DabRuntimeError(
                "internal Modern return normalization requires a result register");
        }
        const auto valid_register = [this](dab_register_t reg)
        {
            return !reg.nil() && reg.value() < _registers.size() &&
                   _registers[reg.value()].data.type != TYPE_INVALID;
        };
        if (!valid_register(reglist[0]))
        {
            throw DabRuntimeError(
                "internal Modern return normalization received an invalid value register");
        }
        if (!valid_register(reglist[1]))
        {
            throw DabRuntimeError(
                "internal Modern return normalization received an invalid target register");
        }
        const auto target = register_get(reglist[1]);
        if (target.data.type != TYPE_CLASS || !modern_return_supported_class(target.data.fixnum))
        {
            throw DabRuntimeError(
                "internal Modern return normalization expects a supported declared result Class");
        }
        const auto value = register_get(reglist[0]);
        register_set(out_reg,
                     modern_return_normalize(value, static_cast<dab_class_t>(target.data.fixnum)));
        break;
    }
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
    case KERNEL_GET_INSTVAR:
    {
        assert(reglist.size() == 2);
        auto self  = register_get(reglist[0]);
        auto name  = register_get(reglist[1]);
        auto value = self.get_instvar(get_or_create_symbol_index(name.string()));
        register_set(out_reg, value);
        break;
    }
    case KERNEL_SET_INSTVAR:
    {
        assert(reglist.size() == 3);
        auto self  = register_get(reglist[0]);
        auto name  = register_get(reglist[1]);
        auto value = register_get(reglist[2]);
        self.set_instvar(get_or_create_symbol_index(name.string()), value);
        register_set(out_reg, nullptr);
        break;
    }
    case KERNEL_ANSI_COLOR:
    {
        std::string ret;
        ret += "\e[";
        for (int i = 0; i < (int)reglist.size(); i++)
        {
            if (i > 0)
            {
                ret += ";";
            }
            char data[16];
            auto v = register_get(reglist[i]);
            assert(v.data.type == TYPE_FIXNUM);
            auto n = v.data.fixnum;
            snprintf(data, 16, "%d", (int)n);
            ret += data;
        }
        ret += "m";
        //        fprintf(stderr, "VM: ANSI [%s]\n", ret.c_str());
        register_set(out_reg, ret);
        break;
    }
    default:
        fprintf(stderr, "VM error: Unknown kernel call <%d>.\n", (int)call);
        exit(1);
        break;
    }
}
