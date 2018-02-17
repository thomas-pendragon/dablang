#include "cvm.h"

#include "defaults_shared.h"

#define CREATE_INT_CLASS(small, BIG)                                                               \
    auto &small##_class = get_class(CLASS_##BIG);                                                  \
    DAB_MEMBER_NUMERIC_OPERATORS(small##_class, CLASS_##BIG, small##_t, .data.num_##small);

static int32_t byteswap(int32_t value)
{
    return ((value >> 24) & 0x000000FF) | ((value << 8) & 0x00FF0000) |
           ((value >> 8) & 0x0000FF00) | ((value << 24) & 0xFF000000);
}

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

    int32_class.add_reg_function("byteswap", [](DabValue self, std::vector<DabValue> args) {
        assert(args.size() == 0);
        auto     value     = self.data.num_int32;
        auto     new_value = byteswap(value);
        DabValue ret(CLASS_INT32, new_value);
        return ret;
    });

    auto &float_class = get_class(CLASS_FLOAT);
    DAB_MEMBER_BASE_NUMERIC_OPERATORS(float_class, CLASS_FLOAT, float, .data.floatval);
}
