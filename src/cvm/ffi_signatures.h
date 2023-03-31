else if (arg_klasses.size() == 0 && ret_klass == CLASS_UINT64)
{
    typedef uint64_t (*int_fun)();
    auto int_symbol = (int_fun)symbol;

    auto return_value = (*int_symbol)();

    return (DabValue(CLASS_UINT64, return_value));
}
else if (arg_klasses.size() == 1 && arg_klasses[0] == CLASS_INT32 && ret_klass == CLASS_INT32)
{
    typedef int32_t (*int_fun)(int32_t);
    auto int_symbol = (int_fun)symbol;

    auto value0 = $VM->cast(args[0], CLASS_INT32);

    auto value0_data = value0.data.num_int32;

    auto return_value = (*int_symbol)(value0_data);

    return (DabValue(CLASS_INT32, return_value));
}
else if (arg_klasses.size() == 2 && arg_klasses[0] == CLASS_INT32 &&
         arg_klasses[1] == CLASS_INT32 && ret_klass == CLASS_INT32)
{
    typedef int32_t (*int_fun)(int32_t, int32_t);
    auto int_symbol = (int_fun)symbol;

    auto value0 = $VM->cast(args[0], CLASS_INT32);
    auto value1 = $VM->cast(args[1], CLASS_INT32);

    auto value0_data = value0.data.num_int32;
    auto value1_data = value1.data.num_int32;

    auto return_value = (*int_symbol)(value0_data, value1_data);

    return (DabValue(CLASS_INT32, return_value));
}
else if (arg_klasses.size() == 3 && arg_klasses[0] == CLASS_INT32 &&
         arg_klasses[1] == CLASS_INT32 && arg_klasses[2] == CLASS_INT32 && ret_klass == CLASS_INT32)
{
    typedef int32_t (*int_fun)(int32_t, int32_t, int32_t);
    auto int_symbol = (int_fun)symbol;

    auto value0 = $VM->cast(args[0], CLASS_INT32);
    auto value1 = $VM->cast(args[1], CLASS_INT32);
    auto value2 = $VM->cast(args[2], CLASS_INT32);

    auto value0_data = value0.data.num_int32;
    auto value1_data = value1.data.num_int32;
    auto value2_data = value2.data.num_int32;

    auto return_value = (*int_symbol)(value0_data, value1_data, value2_data);

    return (DabValue(CLASS_INT32, return_value));
}
else if (arg_klasses.size() == 5 && arg_klasses[0] == CLASS_INT32 &&
         arg_klasses[1] == CLASS_INT32 && arg_klasses[2] == CLASS_INT32 &&
         arg_klasses[3] == CLASS_INTPTR && arg_klasses[4] == CLASS_INT32 &&
         ret_klass == CLASS_INT32)
{
    typedef int32_t (*int_fun)(int32_t, int32_t, int32_t, void *, int32_t);
    auto int_symbol = (int_fun)symbol;

    auto value0 = $VM->cast(args[0], CLASS_INT32);
    auto value1 = $VM->cast(args[1], CLASS_INT32);
    auto value2 = $VM->cast(args[2], CLASS_INT32);
    auto value3 = $VM->cast(args[3], CLASS_INTPTR);
    auto value4 = $VM->cast(args[4], CLASS_INT32);

    auto value0_data = value0.data.num_int32;
    auto value1_data = value1.data.num_int32;
    auto value2_data = value2.data.num_int32;
    auto value3_data = value3.data.intptr;
    auto value4_data = value4.data.num_int32;

    auto return_value =
        (*int_symbol)(value0_data, value1_data, value2_data, value3_data, value4_data);

    return (DabValue(CLASS_INT32, return_value));
}
else if (arg_klasses.size() == 3 && arg_klasses[0] == CLASS_INT32 &&
         arg_klasses[1] == CLASS_INTPTR && arg_klasses[2] == CLASS_INT32 &&
         ret_klass == CLASS_INT32)
{
    typedef int32_t (*int_fun)(int32_t, void *, int32_t);
    auto int_symbol = (int_fun)symbol;

    auto value0 = $VM->cast(args[0], CLASS_INT32);
    auto value1 = $VM->cast(args[1], CLASS_INTPTR);
    auto value2 = $VM->cast(args[2], CLASS_INT32);

    auto value0_data = value0.data.num_int32;
    auto value1_data = value1.data.intptr;
    auto value2_data = value2.data.num_int32;

    auto return_value = (*int_symbol)(value0_data, value1_data, value2_data);

    return (DabValue(CLASS_INT32, return_value));
}
else if (arg_klasses.size() == 3 && arg_klasses[0] == CLASS_INT32 &&
         arg_klasses[1] == CLASS_INTPTR && arg_klasses[2] == CLASS_UINT64 &&
         ret_klass == CLASS_UINT64)
{
    typedef uint64_t (*int_fun)(int32_t, void *, uint64_t);
    auto int_symbol = (int_fun)symbol;

    auto value0 = $VM->cast(args[0], CLASS_INT32);
    auto value1 = $VM->cast(args[1], CLASS_INTPTR);
    auto value2 = $VM->cast(args[2], CLASS_UINT64);

    auto value0_data = value0.data.num_int32;
    auto value1_data = value1.data.intptr;
    auto value2_data = value2.data.num_uint64;

    auto return_value = (*int_symbol)(value0_data, value1_data, value2_data);

    return (DabValue(CLASS_UINT64, return_value));
}
else if (arg_klasses.size() == 3 && arg_klasses[0] == CLASS_INT32 &&
         arg_klasses[1] == CLASS_INTPTR && arg_klasses[2] == CLASS_INTPTR &&
         ret_klass == CLASS_INT32)
{
    typedef int32_t (*int_fun)(int32_t, void *, void *);
    auto int_symbol = (int_fun)symbol;

    auto value0 = $VM->cast(args[0], CLASS_INT32);
    auto value1 = $VM->cast(args[1], CLASS_INTPTR);
    auto value2 = $VM->cast(args[2], CLASS_INTPTR);

    auto value0_data = value0.data.num_int32;
    auto value1_data = value1.data.intptr;
    auto value2_data = value2.data.intptr;

    auto return_value = (*int_symbol)(value0_data, value1_data, value2_data);

    return (DabValue(CLASS_INT32, return_value));
}
else if (arg_klasses.size() == 1 && arg_klasses[0] == CLASS_STRING && ret_klass == CLASS_UINT64)
{
    typedef uint64_t (*int_fun)(const char *);
    auto int_symbol = (int_fun)symbol;

    auto value0 = $VM->cast(args[0], CLASS_STRING);

    auto value0_store = value0.string();
    auto value0_data  = value0_store.c_str();

    auto return_value = (*int_symbol)(value0_data);

    return (DabValue(CLASS_UINT64, return_value));
}
else if (arg_klasses.size() == 1 && arg_klasses[0] == CLASS_STRING && ret_klass == CLASS_INTPTR)
{
    typedef void *(*int_fun)(const char *);
    auto int_symbol = (int_fun)symbol;

    auto value0 = $VM->cast(args[0], CLASS_STRING);

    auto value0_store = value0.string();
    auto value0_data  = value0_store.c_str();

    auto return_value = (*int_symbol)(value0_data);

    return (DabValue(CLASS_INTPTR, return_value));
}
else if (arg_klasses.size() == 6 && arg_klasses[0] == CLASS_STRING &&
         arg_klasses[1] == CLASS_INT32 && arg_klasses[2] == CLASS_INT32 &&
         arg_klasses[3] == CLASS_INT32 && arg_klasses[4] == CLASS_INT32 &&
         arg_klasses[5] == CLASS_UINT32 && ret_klass == CLASS_INTPTR)
{
    typedef void *(*int_fun)(const char *, int32_t, int32_t, int32_t, int32_t, uint32_t);
    auto int_symbol = (int_fun)symbol;

    auto value0 = $VM->cast(args[0], CLASS_STRING);
    auto value1 = $VM->cast(args[1], CLASS_INT32);
    auto value2 = $VM->cast(args[2], CLASS_INT32);
    auto value3 = $VM->cast(args[3], CLASS_INT32);
    auto value4 = $VM->cast(args[4], CLASS_INT32);
    auto value5 = $VM->cast(args[5], CLASS_UINT32);

    auto value0_store = value0.string();
    auto value0_data  = value0_store.c_str();
    auto value1_data  = value1.data.num_int32;
    auto value2_data  = value2.data.num_int32;
    auto value3_data  = value3.data.num_int32;
    auto value4_data  = value4.data.num_int32;
    auto value5_data  = value5.data.num_uint32;

    auto return_value =
        (*int_symbol)(value0_data, value1_data, value2_data, value3_data, value4_data, value5_data);

    return (DabValue(CLASS_INTPTR, return_value));
}
else if (arg_klasses.size() == 1 && arg_klasses[0] == CLASS_UINT32 && ret_klass == CLASS_INT32)
{
    typedef int32_t (*int_fun)(uint32_t);
    auto int_symbol = (int_fun)symbol;

    auto value0 = $VM->cast(args[0], CLASS_UINT32);

    auto value0_data = value0.data.num_uint32;

    auto return_value = (*int_symbol)(value0_data);

    return (DabValue(CLASS_INT32, return_value));
}
else if (arg_klasses.size() == 1 && arg_klasses[0] == CLASS_UINT32 && ret_klass == CLASS_NILCLASS)
{
    typedef void (*int_fun)(uint32_t);
    auto int_symbol = (int_fun)symbol;

    auto value0 = $VM->cast(args[0], CLASS_UINT32);

    auto value0_data = value0.data.num_uint32;

    (*int_symbol)(value0_data);

    return (DabValue(nullptr));
}
else if (arg_klasses.size() == 1 && arg_klasses[0] == CLASS_INTPTR && ret_klass == CLASS_INT32)
{
    typedef int32_t (*int_fun)(void *);
    auto int_symbol = (int_fun)symbol;

    auto value0 = $VM->cast(args[0], CLASS_INTPTR);

    auto value0_data = value0.data.intptr;

    auto return_value = (*int_symbol)(value0_data);

    return (DabValue(CLASS_INT32, return_value));
}
else if (arg_klasses.size() == 1 && arg_klasses[0] == CLASS_INTPTR && ret_klass == CLASS_INT32)
{
    typedef int32_t (*int_fun)(void *);
    auto int_symbol = (int_fun)symbol;

    auto value0 = $VM->cast(args[0], CLASS_INTPTR);

    auto value0_data = value0.data.intptr;

    auto return_value = (*int_symbol)(value0_data);

    return (DabValue(CLASS_INT32, return_value));
}
else if (arg_klasses.size() == 1 && arg_klasses[0] == CLASS_INTPTR && ret_klass == CLASS_STRING)
{
    typedef const char *(*int_fun)(void *);
    auto int_symbol = (int_fun)symbol;

    auto value0 = $VM->cast(args[0], CLASS_INTPTR);

    auto value0_data = value0.data.intptr;

    auto return_value = (*int_symbol)(value0_data);

    return (DabValue(CLASS_STRING, return_value));
}
else if (arg_klasses.size() == 1 && arg_klasses[0] == CLASS_INTPTR && ret_klass == CLASS_UINT32)
{
    typedef uint32_t (*int_fun)(void *);
    auto int_symbol = (int_fun)symbol;

    auto value0 = $VM->cast(args[0], CLASS_INTPTR);

    auto value0_data = value0.data.intptr;

    auto return_value = (*int_symbol)(value0_data);

    return (DabValue(CLASS_UINT32, return_value));
}
else if (arg_klasses.size() == 1 && arg_klasses[0] == CLASS_INTPTR && ret_klass == CLASS_NILCLASS)
{
    typedef void (*int_fun)(void *);
    auto int_symbol = (int_fun)symbol;

    auto value0 = $VM->cast(args[0], CLASS_INTPTR);

    auto value0_data = value0.data.intptr;

    (*int_symbol)(value0_data);

    return (DabValue(nullptr));
}
else if (arg_klasses.size() == 1 && arg_klasses[0] == CLASS_INTPTR && ret_klass == CLASS_INTPTR)
{
    typedef void *(*int_fun)(void *);
    auto int_symbol = (int_fun)symbol;

    auto value0 = $VM->cast(args[0], CLASS_INTPTR);

    auto value0_data = value0.data.intptr;

    auto return_value = (*int_symbol)(value0_data);

    return (DabValue(CLASS_INTPTR, return_value));
}
else if (arg_klasses.size() == 2 && arg_klasses[0] == CLASS_INTPTR &&
         arg_klasses[1] == CLASS_INT32 && ret_klass == CLASS_INT32)
{
    typedef int32_t (*int_fun)(void *, int32_t);
    auto int_symbol = (int_fun)symbol;

    auto value0 = $VM->cast(args[0], CLASS_INTPTR);
    auto value1 = $VM->cast(args[1], CLASS_INT32);

    auto value0_data = value0.data.intptr;
    auto value1_data = value1.data.num_int32;

    auto return_value = (*int_symbol)(value0_data, value1_data);

    return (DabValue(CLASS_INT32, return_value));
}
else if (arg_klasses.size() == 2 && arg_klasses[0] == CLASS_INTPTR &&
         arg_klasses[1] == CLASS_INT32 && ret_klass == CLASS_INTPTR)
{
    typedef void *(*int_fun)(void *, int32_t);
    auto int_symbol = (int_fun)symbol;

    auto value0 = $VM->cast(args[0], CLASS_INTPTR);
    auto value1 = $VM->cast(args[1], CLASS_INT32);

    auto value0_data = value0.data.intptr;
    auto value1_data = value1.data.num_int32;

    auto return_value = (*int_symbol)(value0_data, value1_data);

    return (DabValue(CLASS_INTPTR, return_value));
}
else if (arg_klasses.size() == 3 && arg_klasses[0] == CLASS_INTPTR &&
         arg_klasses[1] == CLASS_INT32 && arg_klasses[2] == CLASS_INT32 && ret_klass == CLASS_INT32)
{
    typedef int32_t (*int_fun)(void *, int32_t, int32_t);
    auto int_symbol = (int_fun)symbol;

    auto value0 = $VM->cast(args[0], CLASS_INTPTR);
    auto value1 = $VM->cast(args[1], CLASS_INT32);
    auto value2 = $VM->cast(args[2], CLASS_INT32);

    auto value0_data = value0.data.intptr;
    auto value1_data = value1.data.num_int32;
    auto value2_data = value2.data.num_int32;

    auto return_value = (*int_symbol)(value0_data, value1_data, value2_data);

    return (DabValue(CLASS_INT32, return_value));
}
else if (arg_klasses.size() == 3 && arg_klasses[0] == CLASS_INTPTR &&
         arg_klasses[1] == CLASS_INT32 && arg_klasses[2] == CLASS_INT32 &&
         ret_klass == CLASS_INTPTR)
{
    typedef void *(*int_fun)(void *, int32_t, int32_t);
    auto int_symbol = (int_fun)symbol;

    auto value0 = $VM->cast(args[0], CLASS_INTPTR);
    auto value1 = $VM->cast(args[1], CLASS_INT32);
    auto value2 = $VM->cast(args[2], CLASS_INT32);

    auto value0_data = value0.data.intptr;
    auto value1_data = value1.data.num_int32;
    auto value2_data = value2.data.num_int32;

    auto return_value = (*int_symbol)(value0_data, value1_data, value2_data);

    return (DabValue(CLASS_INTPTR, return_value));
}
else if (arg_klasses.size() == 5 && arg_klasses[0] == CLASS_INTPTR &&
         arg_klasses[1] == CLASS_INT32 && arg_klasses[2] == CLASS_INT32 &&
         arg_klasses[3] == CLASS_INT32 && arg_klasses[4] == CLASS_INT32 && ret_klass == CLASS_INT32)
{
    typedef int32_t (*int_fun)(void *, int32_t, int32_t, int32_t, int32_t);
    auto int_symbol = (int_fun)symbol;

    auto value0 = $VM->cast(args[0], CLASS_INTPTR);
    auto value1 = $VM->cast(args[1], CLASS_INT32);
    auto value2 = $VM->cast(args[2], CLASS_INT32);
    auto value3 = $VM->cast(args[3], CLASS_INT32);
    auto value4 = $VM->cast(args[4], CLASS_INT32);

    auto value0_data = value0.data.intptr;
    auto value1_data = value1.data.num_int32;
    auto value2_data = value2.data.num_int32;
    auto value3_data = value3.data.num_int32;
    auto value4_data = value4.data.num_int32;

    auto return_value =
        (*int_symbol)(value0_data, value1_data, value2_data, value3_data, value4_data);

    return (DabValue(CLASS_INT32, return_value));
}
else if (arg_klasses.size() == 3 && arg_klasses[0] == CLASS_INTPTR &&
         arg_klasses[1] == CLASS_INT32 && arg_klasses[2] == CLASS_UINT32 &&
         ret_klass == CLASS_INTPTR)
{
    typedef void *(*int_fun)(void *, int32_t, uint32_t);
    auto int_symbol = (int_fun)symbol;

    auto value0 = $VM->cast(args[0], CLASS_INTPTR);
    auto value1 = $VM->cast(args[1], CLASS_INT32);
    auto value2 = $VM->cast(args[2], CLASS_UINT32);

    auto value0_data = value0.data.intptr;
    auto value1_data = value1.data.num_int32;
    auto value2_data = value2.data.num_uint32;

    auto return_value = (*int_symbol)(value0_data, value1_data, value2_data);

    return (DabValue(CLASS_INTPTR, return_value));
}
else if (arg_klasses.size() == 2 && arg_klasses[0] == CLASS_INTPTR &&
         arg_klasses[1] == CLASS_STRING && ret_klass == CLASS_INT32)
{
    typedef int32_t (*int_fun)(void *, const char *);
    auto int_symbol = (int_fun)symbol;

    auto value0 = $VM->cast(args[0], CLASS_INTPTR);
    auto value1 = $VM->cast(args[1], CLASS_STRING);

    auto value0_data  = value0.data.intptr;
    auto value1_store = value1.string();
    auto value1_data  = value1_store.c_str();

    auto return_value = (*int_symbol)(value0_data, value1_data);

    return (DabValue(CLASS_INT32, return_value));
}
else if (arg_klasses.size() == 2 && arg_klasses[0] == CLASS_INTPTR &&
         arg_klasses[1] == CLASS_STRING && ret_klass == CLASS_INTPTR)
{
    typedef void *(*int_fun)(void *, const char *);
    auto int_symbol = (int_fun)symbol;

    auto value0 = $VM->cast(args[0], CLASS_INTPTR);
    auto value1 = $VM->cast(args[1], CLASS_STRING);

    auto value0_data  = value0.data.intptr;
    auto value1_store = value1.string();
    auto value1_data  = value1_store.c_str();

    auto return_value = (*int_symbol)(value0_data, value1_data);

    return (DabValue(CLASS_INTPTR, return_value));
}
else if (arg_klasses.size() == 8 && arg_klasses[0] == CLASS_INTPTR &&
         arg_klasses[1] == CLASS_STRING && arg_klasses[2] == CLASS_INT32 &&
         arg_klasses[3] == CLASS_INTPTR && arg_klasses[4] == CLASS_INTPTR &&
         arg_klasses[5] == CLASS_INTPTR && arg_klasses[6] == CLASS_INTPTR &&
         arg_klasses[7] == CLASS_INT32 && ret_klass == CLASS_INTPTR)
{
    typedef void *(*int_fun)(void *, const char *, int32_t, void *, void *, void *, void *,
                             int32_t);
    auto int_symbol = (int_fun)symbol;

    auto value0 = $VM->cast(args[0], CLASS_INTPTR);
    auto value1 = $VM->cast(args[1], CLASS_STRING);
    auto value2 = $VM->cast(args[2], CLASS_INT32);
    auto value3 = $VM->cast(args[3], CLASS_INTPTR);
    auto value4 = $VM->cast(args[4], CLASS_INTPTR);
    auto value5 = $VM->cast(args[5], CLASS_INTPTR);
    auto value6 = $VM->cast(args[6], CLASS_INTPTR);
    auto value7 = $VM->cast(args[7], CLASS_INT32);

    auto value0_data  = value0.data.intptr;
    auto value1_store = value1.string();
    auto value1_data  = value1_store.c_str();
    auto value2_data  = value2.data.num_int32;
    auto value3_data  = value3.data.intptr;
    auto value4_data  = value4.data.intptr;
    auto value5_data  = value5.data.intptr;
    auto value6_data  = value6.data.intptr;
    auto value7_data  = value7.data.num_int32;

    auto return_value = (*int_symbol)(value0_data, value1_data, value2_data, value3_data,
                                      value4_data, value5_data, value6_data, value7_data);

    return (DabValue(CLASS_INTPTR, return_value));
}
else if (arg_klasses.size() == 5 && arg_klasses[0] == CLASS_INTPTR &&
         arg_klasses[1] == CLASS_UINT8 && arg_klasses[2] == CLASS_UINT8 &&
         arg_klasses[3] == CLASS_UINT8 && arg_klasses[4] == CLASS_UINT8 && ret_klass == CLASS_INT32)
{
    typedef int32_t (*int_fun)(void *, uint8_t, uint8_t, uint8_t, uint8_t);
    auto int_symbol = (int_fun)symbol;

    auto value0 = $VM->cast(args[0], CLASS_INTPTR);
    auto value1 = $VM->cast(args[1], CLASS_UINT8);
    auto value2 = $VM->cast(args[2], CLASS_UINT8);
    auto value3 = $VM->cast(args[3], CLASS_UINT8);
    auto value4 = $VM->cast(args[4], CLASS_UINT8);

    auto value0_data = value0.data.intptr;
    auto value1_data = value1.data.num_uint8;
    auto value2_data = value2.data.num_uint8;
    auto value3_data = value3.data.num_uint8;
    auto value4_data = value4.data.num_uint8;

    auto return_value =
        (*int_symbol)(value0_data, value1_data, value2_data, value3_data, value4_data);

    return (DabValue(CLASS_INT32, return_value));
}
