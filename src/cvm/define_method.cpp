#include "cvm.h"

void DabVM::kernel_define_method(dab_register_t out_reg, std::vector<dab_register_t> reglist)
{
    //                                  LOAD_METHOD R0, S1
    // /* "foo"        */               LOAD_STRING R1, _DATA + 0, 3
    // /* DEFINE_METHO */               SYSCALL RNIL, 5, R1, R0

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

    fprintf(stderr, "VM: method.data.type: %d (TYPE_METHOD == %d)\n", method.data.type,
            TYPE_METHOD);

    assert(method.data.type == TYPE_METHOD);
    assert(name.data.type == TYPE_LITERALSTRING); // dynamic?

    auto method_symbol = method.data.fixnum;
    auto method_name   = name.string();

    auto fun = functions[method_symbol];
    assert(!fun.new_method);
    auto method_address = fun.address;

    auto method_length = fun.length;
    assert(method_length > 0);

    fprintf(stderr, "VM: define_method %x (%p, len = %d) as '%s'\n", (int)method_address,
            (void *)method_address, (int)method_length, method_name.c_str());

    auto data        = instructions.raw_base_data() + method_address;
    auto new_address = new_instructions.length;
    new_instructions.append(data, method_length);

    DabFunction function;
    function.address    = new_address;
    function.name       = method_name;
    function.new_method = true;
    auto fsymbol        = get_or_create_symbol_index(method_name);
    functions[fsymbol]  = function;

    register_set(out_reg, nullptr);
}
