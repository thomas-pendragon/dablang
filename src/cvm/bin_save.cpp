#include "cvm.h"

void DabVM::dump_vm(FILE *out)
{
    fwrite(instructions.raw_base_data(), instructions.raw_base_length(), 1, out);
}
