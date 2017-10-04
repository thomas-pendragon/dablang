else if (arg_klasses.size() == 1 && arg_klasses[0] == CLASS_INT32 && ret_klass == CLASS_INT32)
{
    typedef int32_t (*int_fun)(int32_t);
    auto int_symbol = (int_fun)symbol;

    auto value0 = $VM->cast(stack.pop_value(), CLASS_INT32);

    auto value0_data = value0.data.num_int32;

    auto return_value = (*int_symbol)(value0_data);

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
    typedef int32_t (*int_fun)(uint32_t);
    auto int_symbol = (int_fun)symbol;

    auto value0 = $VM->cast(stack.pop_value(), CLASS_UINT32);

    auto value0_data = value0.data.num_uint32;

    auto return_value = (*int_symbol)(value0_data);

    stack.push_value(DabValue(CLASS_INT32, return_value));
}
else if (arg_klasses.size() == 1 && arg_klasses[0] == CLASS_INTPTR && ret_klass == CLASS_INT32)
{
    typedef int32_t (*int_fun)(void *);
    auto int_symbol = (int_fun)symbol;

    auto value0 = $VM->cast(stack.pop_value(), CLASS_INTPTR);

    auto value0_data = value0.data.intptr;

    auto return_value = (*int_symbol)(value0_data);

    stack.push_value(DabValue(CLASS_INT32, return_value));
}
else if (arg_klasses.size() == 1 && arg_klasses[0] == CLASS_INTPTR && ret_klass == CLASS_NILCLASS)
{
    typedef void (*int_fun)(void *);
    auto int_symbol = (int_fun)symbol;

    auto value0 = $VM->cast(stack.pop_value(), CLASS_INTPTR);

    auto value0_data = value0.data.intptr;

    (*int_symbol)(value0_data);

    stack.push_value(nullptr);
}
else if (arg_klasses.size() == 1 && arg_klasses[0] == CLASS_UINT32 && ret_klass == CLASS_NILCLASS)
{
    typedef void (*int_fun)(uint32_t);
    auto int_symbol = (int_fun)symbol;

    auto value0 = $VM->cast(stack.pop_value(), CLASS_UINT32);

    auto value0_data = value0.data.num_uint32;

    (*int_symbol)(value0_data);

    stack.push_value(nullptr);
}
else if (arg_klasses.size() == 1 && arg_klasses[0] == CLASS_STRING && ret_klass == CLASS_UINT64)
{
    typedef uint64_t (*int_fun)(const char *);
    auto int_symbol = (int_fun)symbol;

    auto value0 = $VM->cast(stack.pop_value(), CLASS_STRING);

    auto value0_data = value0.data.string.c_str();

    auto return_value = (*int_symbol)(value0_data);

    stack.push_value(DabValue(CLASS_UINT64, return_value));
}
else if (arg_klasses.size() == 3 && arg_klasses[0] == CLASS_INTPTR &&
         arg_klasses[1] == CLASS_INT32 && arg_klasses[2] == CLASS_UINT32 &&
         ret_klass == CLASS_INTPTR)
{
    typedef void *(*int_fun)(void *, int32_t, uint32_t);
    auto int_symbol = (int_fun)symbol;

    auto value2 = $VM->cast(stack.pop_value(), CLASS_UINT32);
    auto value1 = $VM->cast(stack.pop_value(), CLASS_INT32);
    auto value0 = $VM->cast(stack.pop_value(), CLASS_INTPTR);

    auto value0_data = value0.data.intptr;
    auto value1_data = value1.data.num_int32;
    auto value2_data = value2.data.num_uint32;

    auto return_value = (*int_symbol)(value0_data, value1_data, value2_data);

    stack.push_value(DabValue(CLASS_INTPTR, return_value));
}
else if (arg_klasses.size() == 5 && arg_klasses[0] == CLASS_INTPTR &&
         arg_klasses[1] == CLASS_UINT8 && arg_klasses[2] == CLASS_UINT8 &&
         arg_klasses[3] == CLASS_UINT8 && arg_klasses[4] == CLASS_UINT8 && ret_klass == CLASS_INT32)
{
    typedef int32_t (*int_fun)(void *, uint8_t, uint8_t, uint8_t, uint8_t);
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
    typedef int32_t (*int_fun)(void *, int32_t, int32_t, int32_t, int32_t);
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
    typedef void *(*int_fun)(const char *, int32_t, int32_t, int32_t, int32_t, uint32_t);
    auto int_symbol = (int_fun)symbol;

    auto value5 = $VM->cast(stack.pop_value(), CLASS_UINT32);
    auto value4 = $VM->cast(stack.pop_value(), CLASS_INT32);
    auto value3 = $VM->cast(stack.pop_value(), CLASS_INT32);
    auto value2 = $VM->cast(stack.pop_value(), CLASS_INT32);
    auto value1 = $VM->cast(stack.pop_value(), CLASS_INT32);
    auto value0 = $VM->cast(stack.pop_value(), CLASS_STRING);

    auto value0_data = value0.data.string.c_str();
    auto value1_data = value1.data.num_int32;
    auto value2_data = value2.data.num_int32;
    auto value3_data = value3.data.num_int32;
    auto value4_data = value4.data.num_int32;
    auto value5_data = value5.data.num_uint32;

    auto return_value =
        (*int_symbol)(value0_data, value1_data, value2_data, value3_data, value4_data, value5_data);

    stack.push_value(DabValue(CLASS_INTPTR, return_value));
}
else if (arg_klasses.size() == 3 && arg_klasses[0] == CLASS_INT32 &&
         arg_klasses[1] == CLASS_INT32 && arg_klasses[2] == CLASS_INT32 && ret_klass == CLASS_INT32)
{
    typedef int32_t (*int_fun)(int32_t, int32_t, int32_t);
    auto int_symbol = (int_fun)symbol;

    auto value2 = $VM->cast(stack.pop_value(), CLASS_INT32);
    auto value1 = $VM->cast(stack.pop_value(), CLASS_INT32);
    auto value0 = $VM->cast(stack.pop_value(), CLASS_INT32);

    auto value0_data = value0.data.num_int32;
    auto value1_data = value1.data.num_int32;
    auto value2_data = value2.data.num_int32;

    auto return_value = (*int_symbol)(value0_data, value1_data, value2_data);

    stack.push_value(DabValue(CLASS_INT32, return_value));
}
else if (arg_klasses.size() == 5 && arg_klasses[0] == CLASS_INT32 &&
         arg_klasses[1] == CLASS_INT32 && arg_klasses[2] == CLASS_INT32 &&
         arg_klasses[3] == CLASS_INTPTR && arg_klasses[4] == CLASS_INT32 &&
         ret_klass == CLASS_INT32)
{
    typedef int32_t (*int_fun)(int32_t, int32_t, int32_t, void *, int32_t);
    auto int_symbol = (int_fun)symbol;

    auto value4 = $VM->cast(stack.pop_value(), CLASS_INT32);
    auto value3 = $VM->cast(stack.pop_value(), CLASS_INTPTR);
    auto value2 = $VM->cast(stack.pop_value(), CLASS_INT32);
    auto value1 = $VM->cast(stack.pop_value(), CLASS_INT32);
    auto value0 = $VM->cast(stack.pop_value(), CLASS_INT32);

    auto value0_data = value0.data.num_int32;
    auto value1_data = value1.data.num_int32;
    auto value2_data = value2.data.num_int32;
    auto value3_data = value3.data.intptr;
    auto value4_data = value4.data.num_int32;

    auto return_value =
        (*int_symbol)(value0_data, value1_data, value2_data, value3_data, value4_data);

    stack.push_value(DabValue(CLASS_INT32, return_value));
}
else if (arg_klasses.size() == 3 && arg_klasses[0] == CLASS_INT32 &&
         arg_klasses[1] == CLASS_INTPTR && arg_klasses[2] == CLASS_INT32 &&
         ret_klass == CLASS_INT32)
{
    typedef int32_t (*int_fun)(int32_t, void *, int32_t);
    auto int_symbol = (int_fun)symbol;

    auto value2 = $VM->cast(stack.pop_value(), CLASS_INT32);
    auto value1 = $VM->cast(stack.pop_value(), CLASS_INTPTR);
    auto value0 = $VM->cast(stack.pop_value(), CLASS_INT32);

    auto value0_data = value0.data.num_int32;
    auto value1_data = value1.data.intptr;
    auto value2_data = value2.data.num_int32;

    auto return_value = (*int_symbol)(value0_data, value1_data, value2_data);

    stack.push_value(DabValue(CLASS_INT32, return_value));
}
else if (arg_klasses.size() == 2 && arg_klasses[0] == CLASS_INT32 &&
         arg_klasses[1] == CLASS_INT32 && ret_klass == CLASS_INT32)
{
    typedef int32_t (*int_fun)(int32_t, int32_t);
    auto int_symbol = (int_fun)symbol;

    auto value1 = $VM->cast(stack.pop_value(), CLASS_INT32);
    auto value0 = $VM->cast(stack.pop_value(), CLASS_INT32);

    auto value0_data = value0.data.num_int32;
    auto value1_data = value1.data.num_int32;

    auto return_value = (*int_symbol)(value0_data, value1_data);

    stack.push_value(DabValue(CLASS_INT32, return_value));
}
else if (arg_klasses.size() == 3 && arg_klasses[0] == CLASS_INT32 &&
         arg_klasses[1] == CLASS_INTPTR && arg_klasses[2] == CLASS_INTPTR &&
         ret_klass == CLASS_INT32)
{
    typedef int32_t (*int_fun)(int32_t, void *, void *);
    auto int_symbol = (int_fun)symbol;

    auto value2 = $VM->cast(stack.pop_value(), CLASS_INTPTR);
    auto value1 = $VM->cast(stack.pop_value(), CLASS_INTPTR);
    auto value0 = $VM->cast(stack.pop_value(), CLASS_INT32);

    auto value0_data = value0.data.num_int32;
    auto value1_data = value1.data.intptr;
    auto value2_data = value2.data.intptr;

    auto return_value = (*int_symbol)(value0_data, value1_data, value2_data);

    stack.push_value(DabValue(CLASS_INT32, return_value));
}
else if (arg_klasses.size() == 3 && arg_klasses[0] == CLASS_INT32 &&
         arg_klasses[1] == CLASS_INTPTR && arg_klasses[2] == CLASS_UINT64 &&
         ret_klass == CLASS_UINT64)
{
    typedef uint64_t (*int_fun)(int32_t, void *, uint64_t);
    auto int_symbol = (int_fun)symbol;

    auto value2 = $VM->cast(stack.pop_value(), CLASS_UINT64);
    auto value1 = $VM->cast(stack.pop_value(), CLASS_INTPTR);
    auto value0 = $VM->cast(stack.pop_value(), CLASS_INT32);

    auto value0_data = value0.data.num_int32;
    auto value1_data = value1.data.intptr;
    auto value2_data = value2.data.num_uint64;

    auto return_value = (*int_symbol)(value0_data, value1_data, value2_data);

    stack.push_value(DabValue(CLASS_UINT64, return_value));
}
else if (arg_klasses.size() == 1 && arg_klasses[0] == CLASS_STRING && ret_klass == CLASS_INTPTR)
{
    typedef void *(*int_fun)(const char *);
    auto int_symbol = (int_fun)symbol;

    auto value0 = $VM->cast(stack.pop_value(), CLASS_STRING);

    auto value0_data = value0.data.string.c_str();

    auto return_value = (*int_symbol)(value0_data);

    stack.push_value(DabValue(CLASS_INTPTR, return_value));
}
else if (arg_klasses.size() == 1 && arg_klasses[0] == CLASS_INTPTR && ret_klass == CLASS_UINT32)
{
    typedef uint32_t (*int_fun)(void *);
    auto int_symbol = (int_fun)symbol;

    auto value0 = $VM->cast(stack.pop_value(), CLASS_INTPTR);

    auto value0_data = value0.data.intptr;

    auto return_value = (*int_symbol)(value0_data);

    stack.push_value(DabValue(CLASS_UINT32, return_value));
}
else if (arg_klasses.size() == 1 && arg_klasses[0] == CLASS_INTPTR && ret_klass == CLASS_STRING)
{
    typedef const char *(*int_fun)(void *);
    auto int_symbol = (int_fun)symbol;

    auto value0 = $VM->cast(stack.pop_value(), CLASS_INTPTR);

    auto value0_data = value0.data.intptr;

    auto return_value = (*int_symbol)(value0_data);

    stack.push_value(DabValue(CLASS_STRING, return_value));
}
