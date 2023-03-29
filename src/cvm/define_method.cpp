#include "cvm.h"
#include "../cshared/opcodes.h"

void DabVM::kernel_define_method(dab_register_t out_reg, std::vector<dab_register_t> reglist)
{
    assert(reglist.size() == 2);

    auto name   = register_get(reglist[0]);
    auto method = register_get(reglist[1]);

    fprintf(stderr, "VM: define_method\n");
    fprintf(stderr, "VM: method: ");
    method.dump(stderr);
    fprintf(stderr, "\n");
    fprintf(stderr, "VM: name:   ");
    name.dump(stderr);
    fprintf(stderr, "\n");

    fprintf(stderr, "VM: method.data.type: %d (TYPE_METHOD == %d, TYPE_OBJECT = %d)\n",
            method.data.type, TYPE_METHOD, TYPE_OBJECT);

    assert(method.data.type == TYPE_OBJECT);
    assert(name.data.type == TYPE_LITERALSTRING); // dynamic?

    auto &method_class = method.get_class();

    auto method_name = name.string();

    auto real_method_name = std::string("call");
    auto call_symbol      = $VM->get_symbol_index(real_method_name);
    auto fun              = method_class.get_instance_function(call_symbol);
    assert(!fun.new_method);
    auto method_address = fun.address;

    auto method_length = fun.length;
    assert(method_length > 0);

    fprintf(stderr, "VM: define_method %x (%p, len = %d) as '%s'\n", (int)method_address,
            (void *)method_address, (int)method_length, method_name.c_str());

    FILE *output = stderr;
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
        if (object.is_a(fixnum_class))
        {
            auto reg = i * 2;
            auto num = (int)object.data.fixnum;
            fprintf(output, "LOAD_NUMBER R%d, %d\n", reg, num);
            binary_output.write_uint8(OP_LOAD_NUMBER);
            binary_output.write_uint16(reg);
            binary_output.write_int64(num);
        }
        else
        {
            fprintf(stderr, ">> Unsupported object in closure\n");
            object.dump(stderr);
            exit(1);
        }
        auto outbox = i * 2 + 1;
        auto inbox = i * 2;
        fprintf(output, "BOX R%d, R%d\n", outbox, inbox);
        binary_output.write_uint8(OP_BOX);
        binary_output.write_uint16(outbox);
        binary_output.write_uint16(inbox);
    }

    auto class_reg         = (int)closure_array.size() * 2;
    auto method_reg        = class_reg + 1;
    auto asm_out_reg       = method_reg + 1;
    auto new_symbol_index  = $VM->get_or_create_symbol_index("new");
    auto call_symbol_index = $VM->get_or_create_symbol_index("call");
    auto class_index       = method_class.index;

    //    fprintf(output, "NEW_ARRAY R%d", array_reg);

    fprintf(output, "LOAD_CLASS R%d, %d\n", class_reg, class_index);
    binary_output.write_uint8(OP_LOAD_CLASS);
    binary_output.write_uint16(class_reg);
    binary_output.write_uint16(class_index);
    fprintf(output, "INSTCALL R%d, R%d, S%d", method_reg, class_reg, new_symbol_index);
    binary_output.write_uint8(OP_INSTCALL);
    binary_output.write_uint16(method_reg);
    binary_output.write_uint16(class_reg);
    binary_output.write_uint16(new_symbol_index);
    binary_output.write_uint8((int)closure_array.size());
    for (int i = 0; i < (int)closure_array.size(); i++)
    {
        fprintf(output, ", R%d", i * 2 + 1);
        binary_output.write_uint16(i * 2 + 1);
    }
    fprintf(output, "\n");
    fprintf(output, "INSTCALL R%d, R%d, S%d\n", asm_out_reg, method_reg, call_symbol_index);
    binary_output.write_uint8(OP_INSTCALL);
    binary_output.write_uint16(asm_out_reg);
    binary_output.write_uint16(method_reg);
    binary_output.write_uint16(call_symbol_index);
    binary_output.write_uint8(0);
    fprintf(output, "RETURN R%d\n", asm_out_reg);
    binary_output.write_uint8(OP_RETURN);
    binary_output.write_uint16(asm_out_reg);
    
    fprintf(stderr, ">> Written %d binary bytes to stream\n", (int)binary_output.length());
    binary_output.dump(stderr);
    
    auto data        = instructions.raw_base_data() + method_address;
    auto new_address = new_instructions.length;
    new_instructions.append(data, method_length);

    DabFunction function;
    function.address    = new_address;
    function.name       = method_name;
    function.new_method = true;
    function.length     = method_length;
    function.reflection = fun.reflection;
    auto fsymbol        = get_or_create_symbol_index(method_name);
    functions[fsymbol]  = function;

    register_set(out_reg, nullptr);

    exit(1);
}
