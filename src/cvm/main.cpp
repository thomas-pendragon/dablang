#include "cvm.h"

#include "../cshared/opcodes.h"
#include "../cshared/opcodes_format.h"
#include "../cshared/opcodes_debug.h"

DabVM *$VM = nullptr;

DabVM::DabVM()
{
    assert(!$VM);
    $VM = this;
    predefine_default_classes();
}

DabVM::~DabVM()
{
    fprintf(stderr, "vm: VM destroyed!\n");
    shutdown = true;
}

DabVMReset::~DabVMReset()
{
    fprintf(stderr, "vm: reset $VM pointer\n");
    $VM = nullptr;
}

std::string DabVM::get_symbol(dab_symbol_t index) const
{
    if (index == DAB_SYMBOL_NIL)
    {
        return "";
    }
    if (symbols.size() <= index)
    {
        char index_string[32];
        snprintf(index_string, sizeof(index_string), "%d", (int)index);
        throw DabRuntimeError(std::string("symbol ") + index_string + " not found.");
    }
    return symbols[index].value;
}

dab_class_t DabVM::find_class(const std::string &name)
{
    for (const auto &it : classes)
    {
        const auto &klass = it.second;
        if (klass.name == name)
        {
            return it.first;
        }
    }

    fprintf(stderr, "VM error: unknown class with name <%s>.\n", name.c_str());
    exit(1);
}

DabClass &DabVM::get_class(dab_class_t index)
{
    if (!classes.count(index))
    {
        fprintf(stderr, "VM error: unknown class with index <0x%04x>.\n", index);
        exit(1);
    }
    return classes[index];
}

bool DabVM::pop_frame(bool regular)
{
    if (options.verbose)
    {
        fprintf(stderr, "vm: pop %sframe\n", regular ? "regular " : "");
    }

    auto retval  = get_retval();
    auto prev_ip = get_prev_ip();
    auto out_reg = get_out_reg();

    stackframes.pop_back();

    if (regular)
    {
        if (options.verbose)
        {
            fprintf(stderr, "vm: seek ret to %p (%d).\n", (void *)prev_ip, (int)prev_ip);
        }
        instructions.seek(prev_ip);
    }

    _registers = _register_stack.back();
    _register_stack.pop_back();

    if (!out_reg.nil())
    {
        if (options.verbose)
        {
            fprintf(stderr, "vm: set retval at 0x%x\n", out_reg.value());
        }
        register_set(out_reg, retval);
    }

    if (stackframes.size() == 0)
    {
        if (options.verbose)
        {
            fprintf(stderr, "vm: pop last frame prev_ip = %" PRIu64 "\n", prev_ip);
        }
        return false;
    }

    return true;
}

void DabVM::push_new_frame(const DabValue &self,
                           // uint64_t block_addr,
                           dab_register_t out_reg,
                           // const DabValue &capture,
                           std::vector<dab_register_t> reglist)
{
    DabStackFrame stackframe;

    stackframe.self = self;
    for (auto reg : reglist)
    {
        stackframe.args.push_back(register_get(reg));
    }
    stackframe.prev_ip = ip();
    // stackframe.block_addr = block_addr;
    // stackframe.capture    = capture;
    stackframe.out_reg = out_reg;

    stackframes.push_back(stackframe);

    _register_stack.push_back(_registers);
    _registers.resize(0);
}

void DabVM::_dump(const char *name, const std::vector<DabValue> &data, FILE *output)
{
    fprintf(output, "Dump of %s:\n", name);
    for (size_t i = 0; i < data.size(); i++)
    {
        fprintf(output, "[%4zu] ", i);
        data[i].dump(output);
        fprintf(output, "\n");
    }
}

uint64_t DabVM::ip() const
{
    return instructions.position();
}

int DabVM::run(std::vector<Stream> &inputs)
{
    for (auto &stream : inputs)
    {
        instructions.append(stream);
        stream.seek(0);
        if (options.verbose)
        {
            fprintf(stderr,
                    "vm: append %" PRIu64 " bytes to instrucitons stream, now %" PRIu64 "\n",
                    stream.length(), instructions.length());
        }
    }

    if (!options.bare)
    {
        for (auto &stream : inputs)
        {
            load_newformat(stream);
        }
    }

    define_defaults();

    if (options.raw)
    {
        execute(instructions);
    }
    else
    {
        fprintf(stderr, "vm: trying to initialize attributes\n");
        for (auto fn : functions)
        {
            auto symbol = get_symbol(fn.first);
            // fprintf(stderr, "vm: consider attrfun[%s]\n", symbol.c_str());
            if (symbol.find("__init_") != 0)
                continue;

            fprintf(stderr, "vm: initialize attributes (%s)\n", symbol.c_str());
            instructions.rewind();
            call(dab_register_t::nilreg(), fn.first, 0, DAB_SYMBOL_NIL, nullptr);
            execute(instructions);
        }
        // fprintf(stderr, "vm: finished initializing attributes\n");

        instructions.rewind();
        call(dab_register_t::nilreg(), get_symbol_index(options.entry), 0, DAB_SYMBOL_NIL, nullptr);
        if (options.autorun)
        {
            execute(instructions);
        }
        else
        {
            execute_debug(instructions);
        }
    }

    return 0;
}

DabStackFrame *DabVM::current_frame()
{
    if (stackframes.size() == 0)
        return nullptr;
    return &stackframes[stackframes.size() - 1];
}

bool DabVM::has_arg(int arg_index)
{
    return current_frame()->args.size() > (size_t)arg_index;
}

DabValue &DabVM::get_arg(int arg_index)
{
    assert(arg_index < (int)current_frame()->args.size());
    return current_frame()->args[arg_index];
}

DabValue DabVM::get_current_block()
{
    for (auto value : current_frame()->args)
    {
        if (value.localblock)
        {
            return value;
        }
    }
    return DabValue(nullptr);
}

DabValue &DabVM::get_retval()
{
    return current_frame()->retvalue;
}

dab_register_t DabVM::get_out_reg()
{
    return current_frame()->out_reg;
}

DabValue &DabVM::get_self()
{
    return current_frame()->self;
}

uint64_t DabVM::get_prev_ip()
{
    return current_frame()->prev_ip;
}

int DabVM::number_of_args()
{
    return (int)current_frame()->args.size();
}

void DabVM::call(dab_register_t out_reg, dab_symbol_t symbol, int n_args, dab_symbol_t block_symbol,
                 const DabValue &capture, std::vector<dab_register_t> reglist)
{
    if (options.verbose)
    {
        auto name       = get_symbol(symbol);
        auto block_name = get_symbol(block_symbol);
        fprintf(stderr, "vm: call <%s> with %d arguments and <%s> block.\n", name.c_str(), n_args,
                block_name.c_str());
    }
    if (!functions.count(symbol))
    {
        auto name = get_symbol(symbol);
        throw DabRuntimeError("vm error: Unknown function <" + name + ">.");
    }
    assert(block_symbol == DAB_SYMBOL_NIL);
    (void)capture;

    _call_function(false, out_reg, nullptr, functions[symbol], reglist);
}

DabValue DabVM::call_block(const DabValue &self, std::vector<DabValue> args)
{
    (void)self;
    /*
    auto out_reg = input.read_reg();
    auto symbol  = input.read_symbol();
    auto reglist = input.read_reglist();
    call(out_reg, symbol, (int)reglist.size(), DAB_SYMBOL_NIL, nullptr, reglist);
    */
    /*
    void DabVM::_call_function(bool use_self, dab_register_t out_reg, const DabValue &self,
                       const DabFunction &fun, int n_args, void *blockaddress,
                       const DabValue &capture, std::vector<dab_register_t> reglist,
                       DabValue *return_value, size_t stack_pos)
    */
    auto real_self = self.get_instvar(get_or_create_symbol_index("self"));

    auto     symbol = self.data.fixnum;
    auto     reg    = dab_register_t::nilreg();
    DabValue out;
    //    DabValue                    fake_self; // ?
    auto                        fun = $VM->functions[symbol];
    std::vector<dab_register_t> reglist;
    int                         regindex = 1000; // TODO!
    for (auto arg : args)
    {
        auto reg = (dab_register_t)regindex;
        register_set(reg, arg);
        reglist.push_back(reg);
        regindex += 1;
    }

    fprintf(stderr, "vm: will call with self = ");
    real_self.dump(stderr);
    fprintf(stderr, "\n");

    _call_function(false, reg, real_self, fun, reglist);

    return out;
}

void DabVM::_call_function(bool use_self, dab_register_t out_reg, const DabValue &self,
                           const DabFunction &fun,
                           // int n_args, // void *blockaddress,
                           // const DabValue &capture,
                           std::vector<dab_register_t> reglist, DabValue *return_value,
                           size_t stack_pos)
{
    if (options.verbose)
    {
        fprintf(stderr, "vm: call %s <%s> and %d arguments -> 0x%x.\n", fun.regular ? "Dab" : "C++",
                fun.name.c_str(), (int)reglist.size(), out_reg.value());
    }

    if (fun.regular)
    {
        //        (void)capture;

        push_new_frame(self, out_reg, reglist);
        instructions.seek(fun.address);

        if (return_value)
        {
            // temporary hack
            while (stackframes.size() != stack_pos)
            {
                execute_single(instructions);
            }

            *return_value = register_get(out_reg);
        }
    }
    else if (fun.extra_reg)
    {
        std::vector<DabValue> value_list;
        for (auto reg : reglist)
        {
            value_list.push_back(register_get(reg));
        }
        auto out = fun.extra_reg(use_self ? self : DabValue(nullptr), value_list);
        register_set(out_reg, out);
        if (return_value)
        {
            *return_value = out;
        }
    }
}

void DabVM::execute(Stream &input)
{
    while (!input.eof())
    {
        if (!execute_single(input))
        {
            break;
        }
        if (breakpoints.count(ip()))
        {
            return;
        }
    }
}

DabValue DabVM::register_get(dab_register_t reg)
{
    auto reg_index = reg.value();
    if (reg.nil() || _registers.size() <= reg_index)
    {
        return nullptr;
    }
    return _registers[reg_index];
}

void DabVM::register_set(dab_register_t reg, const DabValue &value)
{
    auto reg_index = reg.value();
    if (reg.nil())
    {
        return;
    }

    if (_registers.size() <= reg_index)
    {
        _registers.resize(reg_index + 1);
    }
    _registers[reg_index] = value;
}

void DabVM::reflect(size_t reflection_type, const DabValue &symbol, dab_register_t reg,
                    bool has_class, uint16_t class_index)
{
    switch (reflection_type)
    {
    case REFLECT_METHOD_ARGUMENTS:
    case REFLECT_METHOD_ARGUMENT_NAMES:
        reflect_method_arguments(reflection_type, symbol, reg);
        break;
    case REFLECT_INSTANCE_METHOD_ARGUMENT_TYPES:
    case REFLECT_INSTANCE_METHOD_ARGUMENT_NAMES:
        reflect_instance_method(reflection_type, symbol, reg, has_class, class_index);
        break;
    default:
        fprintf(stderr, "vm: unknown reflection %d\n", (int)reflection_type);
        exit(1);
        break;
    }
}

void DabVM::reflect_method_arguments(size_t reflection_type, const DabValue &symbol,
                                     dab_register_t reg)
{
    if (options.verbose)
    {
        fprintf(stderr, "vm: reflect %d on %s\n", (int)reflection_type, symbol.string().c_str());
    }
    auto        func_index = get_or_create_symbol_index(symbol.string());
    const auto &function   = functions[func_index];

    auto output_names = reflection_type == REFLECT_METHOD_ARGUMENT_NAMES;
    _reflect(function, reg, output_names);
}

void DabVM::reflect_instance_method(size_t reflection_type, const DabValue &symbol,
                                    dab_register_t reg, bool has_class, uint16_t class_index)
{
    assert(has_class);

    auto &klass = get_class(class_index);
    if (options.verbose)
    {
        fprintf(stderr, "vm: reflect %d on %s [%s]\n", (int)reflection_type,
                symbol.string().c_str(), klass.name.c_str());
    }
    auto        dab_symbol = get_or_create_symbol_index(symbol.string());
    const auto &function   = klass.get_instance_function(dab_symbol);

    auto output_names = reflection_type == REFLECT_INSTANCE_METHOD_ARGUMENT_NAMES;
    _reflect(function, reg, output_names);
}

void DabVM::_reflect(const DabFunction &function, dab_register_t reg, bool output_names)
{
    const auto &reflection = function.reflection;

    auto n = reflection.arg_names.size();

    DabValue array_class = classes[CLASS_ARRAY];
    DabValue value       = array_class.create_instance();
    auto    &array       = value.array();
    array.resize(n);

    if (options.verbose)
    {
        fprintf(stderr, "vm: reflect %d arguments\n", (int)n);
    }

    for (size_t i = 0; i < n; i++)
    {
        DabValue arg_value;
        if (output_names)
        {
            arg_value = DabValue(reflection.arg_names[i]);
        }
        else
        {
            auto index = reflection.arg_klasses[i];
            arg_value  = DabValue(classes[index]);
        }
        array[i] = arg_value;
    }

    register_set(reg, value);
}

bool DabVM::execute_single(Stream &input)
{
    auto pos    = input.position();
    auto opcode = input.read_uint8();
    if (options.verbose)
    {
        fprintf(stderr, "@ %d: %d [%s]\n", (int)pos, (int)opcode, g_opcodes[opcode].name.c_str());
    }
    switch (opcode)
    {
    case OP_LOAD_METHOD:
    {
        auto out_reg = input.read_reg();
        auto symbol  = input.read_symbol();

        DabValue value;
        value.data.type   = TYPE_METHOD;
        value.data.fixnum = symbol;

        register_set(out_reg, value);
        break;
    }
    case OP_LOAD_LOCAL_BLOCK:
    {
        auto out_reg = input.read_reg();
        auto in_reg  = input.read_reg();

        auto value = register_get(in_reg);

        // assert(value.data.type == TYPE_METHOD);
        value.localblock = true;

        register_set(out_reg, value);
        break;
    }
    case OP_LOAD_CURRENT_BLOCK:
    {
        auto out_reg = input.read_reg();

        auto value = get_current_block();

        register_set(out_reg, value);
        break;
    }
    case OP_BOX:
    {
        auto out_reg = input.read_reg();
        auto in_reg  = input.read_reg();

        auto value = register_get(in_reg);
        auto box   = DabValue::box(value);

        register_set(out_reg, box);
        break;
    }
    case OP_UNBOX:
    {
        auto out_reg = input.read_reg();
        auto in_reg  = input.read_reg();

        auto value = register_get(in_reg);
        auto box   = DabValue::unbox(value);

        register_set(out_reg, box);
        break;
    }
    case OP_SETBOX:
    {
        auto out_reg    = input.read_reg();
        auto in_reg     = input.read_reg();
        auto newval_reg = input.read_reg();

        auto boxval = register_get(in_reg);
        auto newval = register_get(newval_reg);

        boxval.setbox(newval);

        register_set(out_reg, boxval);
        break;
    }
    case OP_NEW_ARRAY:
    {
        auto out_reg = input.read_reg();
        auto reglist = input.read_reglist();

        auto n = reglist.size();

        DabValue array_class = classes[CLASS_ARRAY];
        DabValue value       = array_class.create_instance();
        auto    &array       = value.array();
        array.resize(n);
        for (size_t i = 0; i < n; i++)
        {
            array[i] = register_get(reglist[i]);
        }
        register_set(out_reg, value);

        break;
    }
    case OP_CALL:
    {
        auto out_reg = input.read_reg();
        auto symbol  = input.read_symbol();
        auto reglist = input.read_reglist();
        call(out_reg, symbol, (int)reglist.size(), DAB_SYMBOL_NIL, nullptr, reglist);
        break;
    }
    case OP_LOAD_STRING:
    {
        auto reg_index = input.read_reg();
        auto address   = input.read_uint64();
        auto length    = input.read_uint64();

        auto &klass        = get_class(CLASS_LITERALSTRING);
        auto  klass_object = DabValue(klass);

        auto instance = klass_object.create_instance();

        auto data = dynamic_cast<DabLiteralString *>(instance.data.object->object);

        data->pointer = instructions.string_ptr(address);
        data->length  = length;

        register_set(reg_index, instance);
        break;
    }
    case OP_LOAD_SELF:
    {
        auto reg_index = input.read_reg();
        register_set(reg_index, get_self());
        break;
    }
    case OP_LOAD_TRUE:
    {
        auto reg_index = input.read_reg();
        register_set(reg_index, DabValue(true));
        break;
    }
    case OP_LOAD_FALSE:
    {
        auto reg_index = input.read_reg();
        register_set(reg_index, DabValue(false));
        break;
    }
    case OP_LOAD_HAS_BLOCK:
    {
        auto reg_index = input.read_reg();
        auto addr      = get_current_block().truthy();
        register_set(reg_index, DabValue(addr));
        break;
    }
    case OP_LOAD_NUMBER:
    {
        auto reg_index = input.read_reg();
        auto number    = input.read_uint64();
        register_set(reg_index, DabValue(number));
        break;
    }
    case OP_REFLECT:
    {
        auto reg_index       = input.read_reg();
        auto symbol_index    = input.read_symbol();
        auto reflection_type = input.read_uint16();
        auto symbol          = get_symbol(symbol_index);

        uint16_t class_index = input.read_uint16();

        reflect(reflection_type, symbol, reg_index, true, class_index);
        break;
    }
    case OP_LOAD_INT8:
    {
        auto     reg_index = input.read_reg();
        auto     n         = input.read_int8();
        DabValue value(CLASS_INT8, n);
        register_set(reg_index, value);
        break;
    }
    case OP_LOAD_INT16:
    {
        auto     reg_index = input.read_reg();
        auto     n         = input.read_int16();
        DabValue value(CLASS_INT16, n);
        register_set(reg_index, value);
        break;
    }
    case OP_LOAD_INT32:
    {
        auto     reg_index = input.read_reg();
        auto     n         = input.read_int32();
        DabValue value(CLASS_INT32, n);
        register_set(reg_index, value);
        break;
    }
    case OP_LOAD_UINT8:
    {
        auto     reg_index = input.read_reg();
        auto     n         = input.read_uint8();
        DabValue value(CLASS_UINT8, n);
        register_set(reg_index, value);
        break;
    }
    case OP_LOAD_UINT16:
    {
        auto     reg_index = input.read_reg();
        auto     n         = input.read_uint16();
        DabValue value(CLASS_UINT16, n);
        register_set(reg_index, value);
        break;
    }
    case OP_LOAD_UINT32:
    {
        auto     reg_index = input.read_reg();
        auto     n         = input.read_uint32();
        DabValue value(CLASS_UINT32, n);
        register_set(reg_index, value);
        break;
    }
    case OP_LOAD_UINT64:
    {
        auto     reg_index = input.read_reg();
        auto     n         = input.read_uint64();
        DabValue value(CLASS_UINT64, n);
        register_set(reg_index, value);
        break;
    }
    case OP_LOAD_INT64:
    {
        auto     reg_index = input.read_reg();
        auto     n         = input.read_int64();
        DabValue value(CLASS_INT64, n);
        register_set(reg_index, value);
        break;
    }
    case OP_LOAD_FLOAT:
    {
        auto     reg_index = input.read_reg();
        auto     n         = input.read_float();
        DabValue value(CLASS_FLOAT, n);
        register_set(reg_index, value);
        break;
    }
    case OP_LOAD_NIL:
    {
        auto reg_index = input.read_reg();
        register_set(reg_index, nullptr);
        break;
    }
    case OP_LOAD_ARG:
    {
        auto reg_index = input.read_reg();
        auto arg_index = input.read_uint16();
        auto var       = get_arg(arg_index);
        register_set(reg_index, var);
        break;
    }
    case OP_LOAD_ARG_DEFAULT:
    {
        auto reg_index = input.read_reg();
        auto arg_index = input.read_uint16();
        auto def_index = input.read_reg();

        DabValue var;
        if (has_arg(arg_index))
        {
            var = get_arg(arg_index);
        }
        else
        {
            var = register_get(def_index);
        }
        register_set(reg_index, var);
        break;
    }
    case OP_LOAD_CLASS_EX:
    {
        auto reg_index   = input.read_reg();
        auto klass_index = input.read_uint16();
        auto reglist     = input.read_reglist();

        std::vector<DabValue> regvalues;
        for (auto reg : reglist)
            regvalues.push_back(register_get(reg));

        auto klass = classes[klass_index];

        int index = 4096;

        klass.name += "<";
        for (auto reg : regvalues)
            klass.name += reg.print_value();
        klass.name += ">";
        klass.index              = index;
        klass.superclass_index   = klass_index;
        klass.templated          = true;
        klass.template_arguments = regvalues;

        classes[index] = klass;

        register_set(reg_index, klass);
        break;
    }
    case OP_LOAD_CLASS:
    {
        auto reg_index   = input.read_reg();
        auto klass_index = input.read_uint16();
        auto klass       = classes[klass_index];
        register_set(reg_index, klass);
        break;
    }
    case OP_MOV:
    {
        auto dst_index = input.read_reg();
        auto src_index = input.read_reg();
        register_set(dst_index, register_get(src_index));
        break;
    }
    case OP_RETURN:
    {
        auto  reg_index = input.read_reg();
        auto  value     = register_get(reg_index);
        auto &retval    = get_retval();
        retval          = value;
        if (!pop_frame(true))
        {
            return false;
        }
        break;
    }
    case OP_JMP:
    {
        auto mod         = input.read_int16() - 3;
        auto new_address = ip() + mod;
        if (options.verbose)
        {
            fprintf(stderr, "JMP(%d), new address: %p -> %p\n", mod, (void *)ip(),
                    (void *)new_address);
        }
        instructions.seek(new_address);
        break;
    }
    case OP_JMP_IF:
    {
        auto value_reg = input.read_reg();
        auto mod_true  = input.read_int16() - 7;
        auto mod_false = input.read_int16() - 7;
        auto value     = register_get(value_reg);
        auto test      = value.truthy();
        instructions.seek(ip() + (test ? mod_true : mod_false));
        break;
    }
    case OP_NOP:
    {
        break;
    }
    case OP_SYSCALL:
    {
        auto reg     = input.read_reg();
        auto call    = input.read_uint8();
        auto reglist = input.read_reglist();
        kernelcall(reg, call, reglist);
        break;
    }
    case OP_INSTCALL:
    {
        auto out_reg  = input.read_reg();
        auto self_reg = input.read_reg();
        auto symbol   = input.read_uint16();
        auto reglist  = input.read_reglist();
        auto n_args   = reglist.size();
        auto recv     = register_get(self_reg);
        if (options.verbose)
        {
            fprintf(stderr, "vm: instcall, recv = ");
            recv.dump(stderr);
            fprintf(stderr, " argc = %d\n", (int)n_args);
        }
        instcall(recv, symbol, n_args, DAB_SYMBOL_NIL, nullptr, out_reg, reglist);
        break;
    }
    case OP_GET_INSTVAR:
    {
        auto out_reg = input.read_reg();
        auto symbol  = input.read_symbol();
        get_instvar(symbol, out_reg);
        break;
    }
    case OP_GET_CLASSVAR:
    {
        auto out_reg = input.read_reg();
        auto symbol  = input.read_symbol();
        get_classvar(symbol, out_reg);
        break;
    }
    case OP_GET_INSTVAR_EXT:
    {
        auto out_reg  = input.read_reg();
        auto symbol   = input.read_symbol();
        auto self_reg = input.read_reg();

        auto self  = register_get(self_reg);
        auto value = self.get_instvar(symbol);
        register_set(out_reg, value);

        break;
    }
    case OP_SET_INSTVAR:
    {
        auto symbol = input.read_symbol();
        auto reg    = input.read_reg();
        auto value  = register_get(reg);
        set_instvar(symbol, value);
        break;
    }
    case OP_SET_CLASSVAR:
    {
        auto symbol = input.read_symbol();
        auto reg    = input.read_reg();
        auto value  = register_get(reg);
        set_classvar(symbol, value);
        break;
    }
    case OP_STACK_RESERVE:
    {
        auto n = input.read_uint16();
        assert(n == 0);
        break;
    }
    case OP_COV:
    {
        auto hash = input.read_uint16();
        auto line = input.read_uint16();
        coverage.add_line(hash, line);
        break;
    }
    case OP_RELEASE:
    {
        auto reg   = input.read_reg();
        auto value = register_get(reg);
        value.release();
        register_set(reg, nullptr);
        break;
    }
    case OP_RETAIN:
    {
        auto reg   = input.read_reg();
        auto value = register_get(reg);
        value.retain();
        break;
    }
    case OP_CAST:
    {
        auto dst_reg     = input.read_reg();
        auto src_reg     = input.read_reg();
        auto klass_index = input.read_uint16();

        auto src = register_get(src_reg);
        auto dst = cast(src, klass_index);

        register_set(dst_reg, dst);

        break;
    }
    default:
        fprintf(stderr, "VM error: Unknown opcode <%02x> (%d).\n", (int)opcode, (int)opcode);
        exit(1);
        break;
    }
    return true;
}

void DabVM::get_instvar(dab_symbol_t symbol, dab_register_t out_reg)
{
    auto value = get_self().get_instvar(symbol);
    register_set(out_reg, value);
}

void DabVM::set_instvar(dab_symbol_t symbol, const DabValue &value)
{
    get_self().set_instvar(symbol, value);
}

void DabVM::get_classvar(dab_symbol_t symbol, dab_register_t out_reg)
{
    auto value = get_self().get_classvar(symbol);
    register_set(out_reg, value);
}

void DabVM::set_classvar(dab_symbol_t symbol, const DabValue &value)
{
    get_self().set_classvar(symbol, value);
}

DabValue DabVM::cast(const DabValue &value, dab_class_t klass_index)
{
    auto from = value.class_index();
    auto to   = klass_index;

    if (from == to)
    {
        return value;
    }

    auto from_fixnum = from == CLASS_FIXNUM;
    auto to_fixnum   = to == CLASS_FIXNUM;

    if (from_fixnum && to == CLASS_UINT8)
    {
        return DabValue(to, (uint8_t)value.data.fixnum);
    }
    else if (from == CLASS_UINT8 && to_fixnum)
    {
        DabValue copy;
        copy.data.type   = TYPE_FIXNUM;
        copy.data.fixnum = value.data.num_uint8;
        return copy;
    }
    else if (from == CLASS_INT32 && to_fixnum)
    {
        DabValue copy;
        copy.data.type   = TYPE_FIXNUM;
        copy.data.fixnum = value.data.num_int32;
        return copy;
    }
    else if (from_fixnum && to == CLASS_UINT32)
    {
        return DabValue(to, (uint32_t)value.data.fixnum);
    }
    else if (from_fixnum && to == CLASS_UINT64)
    {
        return DabValue(to, (uint64_t)value.data.fixnum);
    }
    else if (from_fixnum && to == CLASS_INT8)
    {
        return DabValue(to, (int8_t)value.data.fixnum);
    }
    else if (from_fixnum && to == CLASS_INT16)
    {
        return DabValue(to, (int16_t)value.data.fixnum);
    }
    else if (from_fixnum && to == CLASS_INT32)
    {
        return DabValue(to, (int32_t)value.data.fixnum);
    }
    else if (from_fixnum && to == CLASS_INT64)
    {
        return DabValue(to, (int64_t)value.data.fixnum);
    }
    else if (from == CLASS_UINT32 && to == CLASS_INT32)
    {
        return DabValue(to, (int32_t)value.data.num_uint32);
    }
    else if (from == CLASS_INT32 && to == CLASS_UINT64)
    {
        return DabValue(to, (uint64_t)value.data.num_int32);
    }
    else if (from == CLASS_INT8 && to_fixnum)
    {
        DabValue copy;
        copy.data.type   = TYPE_FIXNUM;
        copy.data.fixnum = value.data.num_int8;
        return copy;
    }
    else if (from == CLASS_UINT32 && to_fixnum)
    {
        DabValue copy;
        copy.data.type   = TYPE_FIXNUM;
        copy.data.fixnum = value.data.num_uint32;
        return copy;
    }
    else if (from == CLASS_UINT64 && to_fixnum)
    {
        DabValue copy;
        copy.data.type   = TYPE_FIXNUM;
        copy.data.fixnum = value.data.num_uint64;
        return copy;
    }
    else if (from == CLASS_NILCLASS && to == CLASS_INTPTR)
    {
        DabValue copy;
        copy.data.type   = TYPE_INTPTR;
        copy.data.intptr = nullptr;
        return copy;
    }
    else if (from == CLASS_STRING && to == CLASS_INTPTR)
    {
        DabValue copy;
        copy.data.type   = TYPE_INTPTR;
        copy.data.intptr = (void *)value.string().c_str();
        return copy;
    }
    else if (from == CLASS_DYNAMICSTRING && to == CLASS_INTPTR)
    {
        DabValue copy;
        copy.data.type = TYPE_INTPTR;
        // TODO: make this better (and less leaky)
        auto str         = value.string();
        auto cstr        = strdup(str.c_str());
        copy.data.intptr = (void *)cstr;
        return copy;
    }
    else if (from == CLASS_BYTEBUFFER && to == CLASS_INTPTR)
    {
        DabValue copy;
        copy.data.type   = TYPE_INTPTR;
        copy.data.intptr = &value.bytebuffer()[0];
        return copy;
    }
    else if (from == CLASS_INTPTR && to == CLASS_STRING)
    {
        return DabValue::allocate_dynstr((const char *)value.data.intptr);
    }
    else if (from == CLASS_LITERALSTRING && to == CLASS_STRING)
    {
        return DabValue::allocate_dynstr(value.string().c_str());
    }
    else if (from == CLASS_DYNAMICSTRING && to == CLASS_STRING)
    {
        return value;
    }
    else if (from == CLASS_FIXNUM && to == CLASS_FLOAT)
    {
        return DabValue(CLASS_FLOAT, (float)value.data.fixnum);
    }
    else if (from == CLASS_BYTEBUFFER && to == CLASS_STRING)
    {
        return DabValue::allocate_dynstr((const char *)&value.bytebuffer()[0]);
    }
    else if (from == CLASS_LITERALSTRING && to == CLASS_INTPTR)
    {
        DabValue copy;
        copy.data.type   = TYPE_INTPTR;
        auto proxy       = value.data.object;
        auto object      = dynamic_cast<DabLiteralString *>(proxy->object);
        copy.data.intptr = (void *)object->pointer;
        return copy;
    }
    else
    {
        char info[256];
        snprintf(info, sizeof(info), "cannot cast %s (%d) to %s (%d)", value.class_name().c_str(),
                 (int)value.class_index(), get_class(klass_index).name.c_str(), (int)klass_index);
        throw DabCastError(info);
    }
}

void DabVM::add_class(const std::string &name, dab_class_t index, dab_class_t parent_index)
{
    if (!classes.count(index))
    {
        auto &parent = classes[parent_index];
        fprintf(stderr, "vm: add class <%s> (parent = <%s>).\n", name.c_str(), parent.name.c_str());
        DabClass klass;
        klass.name             = name;
        klass.index            = index;
        klass.builtin          = false;
        klass.superclass_index = parent_index;
        classes[index]         = klass;
    }
}

DabValue DabVM::cinstcall(DabValue self, const std::string &name, std::vector<DabValue> args)
{
    auto stack_pos = stackframes.size();
    auto symbol    = get_or_create_symbol_index(name);

    std::vector<DabValue> reg_copy;
    reg_copy.resize(args.size() + 1);

    DabValue                    ret;
    dab_register_t              outreg = 0;
    std::vector<dab_register_t> argregs;

    for (size_t i = 0; i < reg_copy.size(); i++)
    {
        dab_register_t reg = (uint16_t)i;

        reg_copy[i] = register_get(reg);

        if (i > 0)
        {
            argregs.push_back(reg);
            register_set(reg, args[i - 1]);
        }
    }

    assert(argregs.size() == args.size());

    instcall(self, symbol, args.size(), DAB_SYMBOL_NIL, nullptr, outreg, argregs, &ret, stack_pos);

    for (size_t i = 0; i < reg_copy.size(); i++)
    {
        dab_register_t reg = (uint16_t)i;

        register_set(reg, reg_copy[i]);
    }

    return ret;
}

void DabVM::instcall(const DabValue &recv, dab_symbol_t symbol, size_t n_args,
                     dab_symbol_t block_symbol, const DabValue &capture, dab_register_t outreg,
                     std::vector<dab_register_t> reglist, DabValue *return_value, size_t stack_pos)
{
    auto  class_index = recv.class_index();
    auto &klass       = get_class(class_index);

    bool  use_static_func = recv.data.type == TYPE_CLASS;
    auto &fun =
        use_static_func ? klass.get_static_function(symbol) : klass.get_instance_function(symbol);

    assert(block_symbol == DAB_SYMBOL_NIL);
    (void)capture;
    (void)n_args;

    _call_function(true, outreg, recv, fun, reglist, return_value, stack_pos);
}

dab_symbol_t DabVM::get_or_create_symbol_index(const std::string &string)
{
    for (dab_symbol_t i = 0; i < (dab_symbol_t)symbols.size(); i++)
    {
        auto &symbol = symbols[i];
        if (symbol.value == string)
        {
            return i;
        }
    }
    DabSymbol symbol;
    symbol.value       = string;
    symbol.source_ring = last_ring_offset;
    symbols.push_back(symbol);
    return (dab_symbol_t)(symbols.size() - 1);
}

DabFunction &DabVM::add_function(uint64_t address, const std::string &name, uint16_t class_index,
                                 bool is_static)
{
    fprintf(stderr, "vm: add function <%s>.\n", name.c_str());
    DabFunction function;
    function.address = address;
    function.name    = name;
    auto func_index  = get_or_create_symbol_index(name);
    if (class_index == 0xFFFF)
    {
        functions[func_index] = function;
        return functions[func_index];
    }
    else
    {
        auto &klass = get_class(class_index);

        if (is_static)
        {
            return klass.static_functions[func_index] = function;
        }
        else
        {
            return klass.functions[func_index] = function;
        }
    }
}

void DabVM::extract(const std::string &name)
{
    FILE *output = options.output;

    if (name == "rip")
    {
        fprintf(output, "%" PRIu64, ip());
    }
    else if (name == "output")
    {
    }
    else if (name == "leaktest")
    {
        run_leaktest(output);
    }
    else if (name == "reg[0]")
    {
        register_get(0).dump(output);
    }
    else if (name == "reg[1]")
    {
        register_get(1).dump(output);
    }
    else if (name == "dumpvm")
    {
        dump_vm(output);
    }
    else
    {
        fprintf(stderr, "vm: unknown extract option <%s>.\n", name.c_str());
        exit(1);
    }
}

bool DabVM::run_leaktest(FILE *output)
{
    bool error = false;
    if (DabMemoryCounter<COUNTER_OBJECT>::counter() > 0)
    {
        fprintf(output, "leaktest: %zu allocated objects remaining\n",
                DabMemoryCounter<COUNTER_OBJECT>::counter());
        error = true;
    }
    if (DabMemoryCounter<COUNTER_PROXY>::counter() > 0)
    {
        fprintf(output, "leaktest: %zu allocated proxies remaining\n",
                DabMemoryCounter<COUNTER_PROXY>::counter());
        error = true;
    }
    if (DabMemoryCounter<COUNTER_VALUE>::counter() > 0)
    {
        fprintf(output, "leaktest: %zu allocated values remaining\n",
                DabMemoryCounter<COUNTER_VALUE>::counter());
        error = true;
    }
    if (!error)
    {
        fprintf(output, "leaktest: no leaks\n");
    }
    return error;
}

void DabRunOptions::parse(const std::vector<std::string> &args)
{
    std::map<std::string, bool>        flags;
    std::map<std::string, std::string> options;
    std::vector<std::string>           others;

    for (auto &arg : args)
    {
        if (arg.substr(0, 2) == "--")
        {
            auto pos = arg.find("=");
            if (pos != std::string::npos)
            {
                auto argname     = arg.substr(0, pos);
                auto argvalue    = arg.substr(pos + 1);
                options[argname] = argvalue;
            }
            else
            {
                flags[arg] = true;
            }
        }
        else
        {
            others.push_back(arg);
        }
    }

    if (options.count("--stderr"))
    {
        this->console       = fopen(options["--$VM->options.console"].c_str(), "wb");
        this->close_console = true;
    }

    if (options.count("--entry"))
    {
        this->entry = options["--entry"];
    }

    if (flags.count("--leaktest"))
    {
        this->leaktest = true;
    }

    if (options.count("--output"))
    {
        this->extract      = true;
        this->extract_part = options["--output"];
    }

    if (options.count("--out"))
    {
        this->output       = fopen(options["--out"].c_str(), "wb");
        this->close_output = true;
    }

    if (others.size() >= 1)
    {
        this->inputs.clear();
        for (const auto &other : others)
        {
            auto filename = other.c_str();
            auto file     = fopen(filename, "rb");
            if (!file)
            {
                fprintf(stderr, "vm: cannot open file <%s> for reading!\n", filename);
                exit(1);
            }
            this->inputs.push_back(file);
            this->close_file = true;
        }
    }

    //    if (flags["--with-attributes"])
    //    {
    //        this->with_attributes = true;
    //    }

    if (flags["--verbose"])
    {
        this->verbose = true;
    }

    if (flags["--debug"])
    {
        this->autorun = false;
    }

    if (flags["--raw"])
    {
        this->raw = true;
    }

    if (flags["--bare"])
    {
        this->bare = true;
    }

    if (flags["--cov"])
    {
        this->coverage_testing = true;
    }

    if (flags["--noautorelease"] || flags["--no-autorelease"])
    {
        this->autorelease = false;
    }
}

int unsafe_main(DabVM &vm, int argc, char **argv)
{
    DabRunOptions &options = vm.options;

    std::vector<std::string> args;
    for (int i = 1; i < argc; i++)
    {
        args.push_back(argv[i]);
    }
    options.parse(args);
    fprintf(stderr, "VM options: autorun %s raw %s cov %s\n", options.autorun ? "yes" : "no",
            options.raw ? "yes" : "no", options.coverage_testing ? "yes" : "no");

    std::vector<Stream> streams;

    for (auto file : options.inputs)
    {
        Stream stream;
        byte   buffer[1024];
        while (!feof(file))
        {
            size_t bytes = fread(buffer, 1, 1024, file);
            if (bytes)
            {
                stream.append(buffer, bytes);
            }
        }
        streams.push_back(stream);
    }

    auto ret_value = vm.run(streams);

    auto clear_registers = [&vm]()
    {
        vm.symbols.resize(0);
        vm._registers.resize(0);
        vm._register_stack.resize(0);
    };
    auto leaktest = options.extract_part == "leaktest";
    if (leaktest)
    {
        clear_registers();
    }
    if (options.extract)
    {
        vm.extract(options.extract_part);
    }
    if (!leaktest)
    {
        clear_registers();
    }
    if (options.close_file)
    {
        for (auto file : options.inputs)
        {
            fclose(file);
        }
    }
    if (options.coverage_testing)
    {
        vm.coverage.dump(stdout);
    }
    if (ret_value == 0 && options.leaktest)
    {
        bool leaked = vm.run_leaktest(options.output);
        if (leaked)
        {
            ret_value = 1;
        }
    }
    if (options.close_output)
    {
        fclose(options.output);
    }
    return ret_value;
}

int main(int argc, char **argv)
{
    setup_handlers();

    DabVM vm;
    assert($VM);

    try
    {
        return unsafe_main(vm, argc, argv);
    }
    catch (DabRuntimeError &error)
    {
        fprintf(stderr, "vm: %s.\n", error.what());
        return 1;
    }
}
