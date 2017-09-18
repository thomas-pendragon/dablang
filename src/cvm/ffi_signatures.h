else if (arg_klasses.size() == 1 && arg_klasses[0] == CLASS_INT32 && ret_klass == CLASS_INT32)
{
    typedef int (*int_fun)(int);

    auto int_symbol = (int_fun)symbol;

    auto value = $VM->cast(stack.pop_value(), CLASS_INT32);

    auto value_data = value.data.num_int32;

    auto return_value = (*int_symbol)(value_data);

    stack.push_value(DabValue(CLASS_INT32, return_value));
}
else if (arg_klasses.size() == 0 && ret_klass == CLASS_UINT64)
{
    typedef uint64_t (*int_fun)();

    auto int_symbol = (int_fun)symbol;

    auto return_value = (*int_symbol)();

    stack.push_value(DabValue(CLASS_UINT64, return_value));
}
else if (arg_klasses.size() == 1 && arg_klasses[0] == CLASS_UINT32 && ret_klass == CLASS_INT32)
{
    typedef int (*int_fun)(uint32_t);

    auto int_symbol = (int_fun)symbol;

    auto value = $VM->cast(stack.pop_value(), CLASS_UINT32);

    auto value_data = value.data.num_uint32;

    auto return_value = (*int_symbol)(value_data);

    stack.push_value(DabValue(CLASS_INT32, return_value));
}
else if (arg_klasses.size() == 1 && arg_klasses[0] == CLASS_INTPTR && ret_klass == CLASS_INT32)
{
    typedef int (*int_fun)(void *);

    auto int_symbol = (int_fun)symbol;

    auto value = $VM->cast(stack.pop_value(), CLASS_INTPTR);
    assert(value.class_index() == CLASS_INTPTR);

    auto value_data = value.data.intptr;

    auto return_value = (*int_symbol)(value_data);
    if ($VM->verbose)
    {
        fprintf(stderr, "vm: ffi int(void*): (%p) -> %d\n", value_data, return_value);
    }

    stack.push_value(DabValue(CLASS_INT32, return_value));
}
else if (arg_klasses.size() == 1 && arg_klasses[0] == CLASS_INTPTR && ret_klass == CLASS_NILCLASS)
{
    typedef void (*int_fun)(void *);

    auto int_symbol = (int_fun)symbol;

    auto value = $VM->cast(stack.pop_value(), CLASS_INTPTR);
    assert(value.class_index() == CLASS_INTPTR);

    auto value_data = value.data.intptr;

    (*int_symbol)(value_data);
    if ($VM->verbose)
    {
        fprintf(stderr, "vm: ffi void(void*): (%p)\n", value_data);
    }

    stack.push_value(DabValue(nullptr));
}
else if (arg_klasses.size() == 1 && arg_klasses[0] == CLASS_UINT32 && ret_klass == CLASS_NILCLASS)
{
    typedef void (*int_fun)(uint32_t);

    auto int_symbol = (int_fun)symbol;

    auto value = $VM->cast(stack.pop_value(), CLASS_UINT32);

    auto value_data = value.data.num_uint32;

    (*int_symbol)(value_data);

    stack.push_value(DabValue(nullptr));
}
else if (arg_klasses.size() == 1 && arg_klasses[0] == CLASS_STRING && ret_klass == CLASS_UINT64)
{
    typedef uint64_t (*int_fun)(const char *);

    auto int_symbol = (int_fun)symbol;

    auto value = stack.pop_value();
    assert(value.class_index() == CLASS_STRING);

    auto value_data = value.data.string.c_str();

    auto return_value = (*int_symbol)(value_data);

    stack.push_value(DabValue(CLASS_UINT64, return_value));
}
else if (arg_klasses.size() == 3 && arg_klasses[0] == CLASS_INTPTR &&
         arg_klasses[1] == CLASS_INT32 && arg_klasses[2] == CLASS_UINT32 &&
         ret_klass == CLASS_INTPTR)
{
    typedef void *(*int_fun)(void *, int, uint32_t);

    auto int_symbol = (int_fun)symbol;

    auto value2 = $VM->cast(stack.pop_value(), CLASS_UINT32);
    auto value1 = $VM->cast(stack.pop_value(), CLASS_INT32);

    auto value = stack.pop_value();
    assert(value.class_index() == CLASS_INTPTR);

    auto value_data  = value.data.intptr;
    auto value1_data = value.data.num_int32;
    auto value2_data = value.data.num_uint32;

    auto return_value = (*int_symbol)(value_data, value1_data, value2_data);

    stack.push_value(DabValue(CLASS_INTPTR, return_value));
}
else if (arg_klasses.size() == 5 && arg_klasses[0] == CLASS_INTPTR &&
         arg_klasses[1] == CLASS_UINT8 && arg_klasses[2] == CLASS_UINT8 &&
         arg_klasses[3] == CLASS_UINT8 && arg_klasses[4] == CLASS_UINT8 && ret_klass == CLASS_INT32)
{
    typedef int (*int_fun)(void *, uint8_t, uint8_t, uint8_t, uint8_t);

    auto int_symbol = (int_fun)symbol;

    auto value4 = $VM->cast(stack.pop_value(), CLASS_UINT8);
    auto value3 = $VM->cast(stack.pop_value(), CLASS_UINT8);
    auto value2 = $VM->cast(stack.pop_value(), CLASS_UINT8);
    auto value1 = $VM->cast(stack.pop_value(), CLASS_UINT8);
    auto value0 = $VM->cast(stack.pop_value(), CLASS_INTPTR);

    auto value0_data = value0.data.intptr;
    auto value1_data = value1.data.num_uint8;
    auto value2_data = value2.data.num_uint8;
    auto value3_data = value3.data.num_uint8;
    auto value4_data = value4.data.num_uint8;

    auto return_value =
        (*int_symbol)(value0_data, value1_data, value2_data, value3_data, value4_data);

    stack.push_value(DabValue(CLASS_INT32, return_value));
}
else if (arg_klasses.size() == 5 && arg_klasses[0] == CLASS_INTPTR &&
         arg_klasses[1] == CLASS_INT32 && arg_klasses[2] == CLASS_INT32 &&
         arg_klasses[3] == CLASS_INT32 && arg_klasses[4] == CLASS_INT32 && ret_klass == CLASS_INT32)
{
    typedef int (*int_fun)(void *, int, int, int, int);

    auto int_symbol = (int_fun)symbol;

    auto value4 = $VM->cast(stack.pop_value(), CLASS_INT32);
    auto value3 = $VM->cast(stack.pop_value(), CLASS_INT32);
    auto value2 = $VM->cast(stack.pop_value(), CLASS_INT32);
    auto value1 = $VM->cast(stack.pop_value(), CLASS_INT32);
    auto value0 = $VM->cast(stack.pop_value(), CLASS_INTPTR);

    auto value0_data = value0.data.intptr;
    auto value1_data = value1.data.num_int32;
    auto value2_data = value2.data.num_int32;
    auto value3_data = value3.data.num_int32;
    auto value4_data = value4.data.num_int32;

    auto return_value =
        (*int_symbol)(value0_data, value1_data, value2_data, value3_data, value4_data);

    stack.push_value(DabValue(CLASS_INT32, return_value));
}
else if (arg_klasses.size() == 6 && arg_klasses[0] == CLASS_STRING &&
         arg_klasses[1] == CLASS_INT32 && arg_klasses[2] == CLASS_INT32 &&
         arg_klasses[3] == CLASS_INT32 && arg_klasses[4] == CLASS_INT32 &&
         arg_klasses[5] == CLASS_UINT32 && ret_klass == CLASS_INTPTR)
{
    typedef void *(*int_fun)(const char *, int, int, int, int, uint32_t);

    auto int_symbol = (int_fun)symbol;

    auto value5 = $VM->cast(stack.pop_value(), CLASS_UINT32);
    auto value4 = $VM->cast(stack.pop_value(), CLASS_INT32);
    auto value3 = $VM->cast(stack.pop_value(), CLASS_INT32);
    auto value2 = $VM->cast(stack.pop_value(), CLASS_INT32);
    auto value1 = $VM->cast(stack.pop_value(), CLASS_INT32);

    auto value0 = stack.pop_value();
    assert(value0.class_index() == CLASS_STRING);

    auto value0_data = value0.data.string.c_str();
    auto value1_data = value1.data.num_int32;
    auto value2_data = value2.data.num_int32;
    auto value3_data = value3.data.num_int32;
    auto value4_data = value4.data.num_int32;
    auto value5_data = value5.data.num_uint32;

    auto return_value =
        (*int_symbol)(value0_data, value1_data, value2_data, value3_data, value4_data, value5_data);

    fprintf(stderr, "vm: ffi void*(const char*, int, int, int, int, uint32_t): (%s, %d, %d, %d, "
                    "%d, %d) -> %p\n",
            value0_data, (int)value1_data, (int)value2_data, (int)value3_data, (int)value4_data,
            (int)value5_data, return_value);

    stack.push_value(DabValue(CLASS_INTPTR, return_value));
}
