#include "cvm.h"

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

    fprintf(stderr, ">> New method:\n_________________________________\n");
    fprintf(output, "STACK_RESERVE 0\n");

    //    auto closure_class_object = DabValue(method_class);
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
            fprintf(output, "LOAD_NUMBER R%d, %d\n", i, (int)object.data.fixnum);
        }
        else
        {
            fprintf(stderr, ">> Unsupported object in closure\n");
            object.dump(stderr);
            exit(1);
        }
    }

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
