#include "cvm.h"

void DabVM::kernel_c_export(dab_register_t out_reg, std::vector<dab_register_t> reglist)
{
    assert(reglist.size() == 1);

    DabValue method = register_get(reglist[0]);
    
    auto     method_name = method.string();

    fprintf(stderr, "vm: c_export '%s'\n", method_name.c_str());

    register_set(out_reg, nullptr);
}
