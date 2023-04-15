#include "cvm.h"
#include "../cshared/opcodes.h"

void DabVM::kernel_define_class(dab_register_t out_reg, std::vector<dab_register_t> reglist)
{
    assert(reglist.size() >= 1);
    assert(reglist.size() <= 2);

    auto        name         = register_get(reglist[0]).string();
    dab_class_t parent_index = CLASS_OBJECT;
    bool        use_parent   = reglist.size() == 2;

    if (use_parent)
    {
        auto parent_name = register_get(reglist[1]).string();
        parent_index     = find_class(parent_name);
    }

    auto max_index = classes.rbegin()->first;
    auto index     = max_index + 1;

    fprintf(stderr, "VM: define_class '%s' as %d (parent = %d)\n", name.c_str(), (int)index,
            (int)parent_index);

    get_or_create_symbol_index(name);
    add_class(name, index, parent_index);

    register_set(out_reg, nullptr);
}

void DabVM::kernel_define_method(dab_register_t out_reg, std::vector<dab_register_t> reglist)
{
    assert(reglist.size() >= 2 && reglist.size() <= 3);

    auto for_class = reglist.size() == 3;

    auto offset = for_class ? 1 : 0;

    auto name   = register_get(reglist[0 + offset]);
    auto method = register_get(reglist[1 + offset]);

    DabValue klass;
    if (for_class)
        klass = register_get(reglist[0]);

    fprintf(stderr, "VM: define_method\n");
    fprintf(stderr, "VM: method: ");
    method.dump(stderr);
    fprintf(stderr, "\n");
    fprintf(stderr, "VM: name:   ");
    name.dump(stderr);
    fprintf(stderr, "\n");
    if (for_class)
    {
        fprintf(stderr, "VM: class:   ");
        klass.dump(stderr);
        fprintf(stderr, "\n");
    }

    fprintf(stderr, "VM: method.data.type: %d (TYPE_METHOD == %d, TYPE_OBJECT = %d)\n",
            method.data.type, TYPE_METHOD, TYPE_OBJECT);

    assert(method.data.type == TYPE_OBJECT);
    assert(name.is_a(get_class(CLASS_STRING)));
    if (for_class)
    {
        assert(klass.data.type == TYPE_CLASS || klass.is_a(get_class(CLASS_STRING)));
    }

    auto &method_class = method.get_class();

    auto method_name = name.string();

    auto real_method_name = std::string("call");
    auto call_symbol      = $VM->get_symbol_index(real_method_name);
    auto fun              = method_class.get_instance_function(call_symbol);

    auto n_args = (int)fun.reflection.arg_names.size();

    fprintf(stderr, "VM: define_method '%s'\n", method_name.c_str());
    fprintf(stderr, "VM: !! fun has %d args\n", n_args);

    FILE  *output = stderr;
    Stream binary_output;

    fprintf(stderr, ">> New method:\n_________________________________\n");
    fprintf(output, "STACK_RESERVE 0\n");
    binary_output.write_uint8(OP_STACK_RESERVE);
    binary_output.write_uint16(0);

    //        auto closure_class_object = DabValue(method_class);
    auto  closure       = method; // closure_class_object.create_instance();
    auto  closure_data  = closure.get_instvar($VM->get_or_create_symbol_index("closure"));
    auto &closure_array = closure_data.array();

    fprintf(stderr, ">> %d objects in closure\n", (int)closure_array.size());

    for (int i = 0; i < (int)closure_array.size(); i++)
    {
        auto object = closure_array[i].unboxed();

        auto fixnum_class = get_class(CLASS_FIXNUM);
        auto string_class = get_class(CLASS_STRING);
        auto reg          = i * 2;
        if (object.is_a(fixnum_class))
        {
            auto num = (int)object.data.fixnum;
            fprintf(output, "LOAD_NUMBER R%d, %d\n", reg, num);
            binary_output.write_uint8(OP_LOAD_NUMBER);
            binary_output.write_uint16(reg);
            binary_output.write_int64(num);
        }
        else if (object.is_a(string_class))
        {
            auto str          = object.string();
            auto new_data_pos = new_data.length;
            new_data.append((const byte *)str.c_str(), str.length() + 1);
            binary_output.write_uint8(OP_LOAD_STRING);
            binary_output.write_uint16(reg);
            fprintf(stderr, "vm: add data offset: %d -> %d\n",
                    (int)(new_instructions.length + binary_output.length()), (int)new_data_pos);
            new_data_offsets.push_back(new_instructions.length + binary_output.length());
            binary_output.write_uint64(new_data_pos);
            binary_output.write_uint64(str.length());
            fprintf(output, "LOAD_STRING R%d, %d, %d\n", (int)reg, (int)new_data_pos,
                    (int)str.length());
        }
        else
        {
            fprintf(stderr, ">> Unsupported object in closure\n");
            object.dump(stderr);
            exit(1);
        }
        auto outbox = i * 2 + 1;
        auto inbox  = i * 2;
        fprintf(output, "BOX R%d, R%d\n", outbox, inbox);
        binary_output.write_uint8(OP_BOX);
        binary_output.write_uint16(outbox);
        binary_output.write_uint16(inbox);
    }

    auto class_reg         = (int)closure_array.size() * 2;
    auto method_reg        = class_reg + 1;
    auto self_reg          = method_reg + 1;
    auto asm_out_reg       = self_reg + 1;
    auto new_symbol_index  = $VM->get_or_create_symbol_index("new");
    auto call_symbol_index = $VM->get_or_create_symbol_index("call");
    auto class_index       = method_class.index;

    //    fprintf(output, "NEW_ARRAY R%d", array_reg);

    fprintf(output, "LOAD_CLASS R%d, %d\n", class_reg, class_index);
    binary_output.write_uint8(OP_LOAD_CLASS);
    binary_output.write_uint16(class_reg);
    binary_output.write_uint16(class_index);
    fprintf(output, "LOAD_SELF R%d\n", self_reg);
    binary_output.write_uint8(OP_LOAD_SELF);
    binary_output.write_uint16(self_reg);
    fprintf(output, "INSTCALL R%d, R%d, S%d", method_reg, class_reg, new_symbol_index);
    binary_output.write_uint8(OP_INSTCALL);
    binary_output.write_uint16(method_reg);
    binary_output.write_uint16(class_reg);
    binary_output.write_uint16(new_symbol_index);
    binary_output.write_uint8(1 + (int)closure_array.size());
    fprintf(output, ", R%d", (int)self_reg);
    binary_output.write_uint16(self_reg);
    for (int i = 0; i < (int)closure_array.size(); i++)
    {
        fprintf(output, ", R%d", i * 2 + 1);
        binary_output.write_uint16(i * 2 + 1);
    }
    fprintf(output, "\n");
    int first_arg_reg = asm_out_reg;
    for (int i = 0; i < n_args; i++)
    {
        fprintf(output, "LOAD_ARG R%d, %d\n", first_arg_reg + i, i);
        binary_output.write_uint8(OP_LOAD_ARG);
        binary_output.write_uint16(first_arg_reg + i);
        binary_output.write_uint16(i);
        asm_out_reg += 1;
    }
    fprintf(output, "INSTCALL R%d, R%d, S%d", asm_out_reg, method_reg, call_symbol_index);
    for (int i = 0; i < n_args; i++)
    {
        fprintf(output, ", R%d", first_arg_reg + i);
    }
    fprintf(output, "\n");
    binary_output.write_uint8(OP_INSTCALL);
    binary_output.write_uint16(asm_out_reg);
    binary_output.write_uint16(method_reg);
    binary_output.write_uint16(call_symbol_index);
    binary_output.write_uint8(n_args);
    for (int i = 0; i < n_args; i++)
    {
        binary_output.write_uint16(first_arg_reg + i);
    }
    fprintf(output, "RETURN R%d\n", asm_out_reg);
    binary_output.write_uint8(OP_RETURN);
    binary_output.write_uint16(asm_out_reg);

    auto method_length = binary_output.length();

    fprintf(stderr, ">> Written %d binary bytes to stream\n", (int)binary_output.length());
    binary_output.dump(stderr);

    //    auto data        = instructions.raw_base_data() + method_address;
    auto data        = binary_output.raw_base_data();
    auto new_address = new_instructions.length;
    new_instructions.append(data, method_length);

    DabFunction function;
    function.address     = new_address;
    function.name        = method_name;
    function.new_method  = true;
    function.length      = method_length;
    function.reflection  = fun.reflection;
    function.source_ring = last_ring_offset;
    auto fsymbol         = get_or_create_symbol_index(method_name);
    if (for_class)
    {
        auto strclass = get_class(CLASS_STRING);
        if (klass.is_a(strclass))
        {
            klass = get_class(find_class(klass.string()));
        }
        auto &klass_data              = klass.get_class();
        klass_data.functions[fsymbol] = function;
    }
    else
    {
        functions[fsymbol] = function;
    }

    register_set(out_reg, nullptr);

    //    exit(1);
}
