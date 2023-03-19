#include "cvm.h"

#include "defaults_shared.h"

#include <math.h>

#define CREATE_INT_CLASS(small, BIG)                                                               \
    auto &small##_class = get_class(CLASS_##BIG);                                                  \
    DAB_MEMBER_NUMERIC_OPERATORS(small##_class, CLASS_##BIG, small##_t, .data.num_##small);

void DabVM::define_default_classes_int()
{
    CREATE_INT_CLASS(uint8, UINT8);
    CREATE_INT_CLASS(uint16, UINT16);
    CREATE_INT_CLASS(uint32, UINT32);
    CREATE_INT_CLASS(uint64, UINT64);

    CREATE_INT_CLASS(int8, INT8);
    CREATE_INT_CLASS(int16, INT16);
    CREATE_INT_CLASS(int32, INT32);
    CREATE_INT_CLASS(int64, INT64);

    auto &float_class = get_class(CLASS_FLOAT);
    DAB_MEMBER_BASE_NUMERIC_OPERATORS(float_class, CLASS_FLOAT, float, .data.floatval);

    float_class.add_reg_function("sqrt",
                                 [](DabValue self, std::vector<DabValue> args)
                                 {
                                     assert(args.size() == 0);
                                     float ret = sqrt(self.data.floatval);
                                     return DabValue(CLASS_FLOAT, ret);
                                 });
}
