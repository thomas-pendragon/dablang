extern "C"
{

    int ffi_simple_test()
    {
        return 4;
    }

    int ffi_arg_test(int a)
    {
        return a * 2 + 1;
    }

    typedef int (*ffi_fun_int_type)(void);
    int ffi_fun_test(ffi_fun_int_type fun)
    {
        return 5 * fun();
    }

    typedef int (*ffi_fun_int_retint_type)(int);
    int ffi_fun_arg_test(ffi_fun_int_retint_type fun)
    {
        return 5 * fun(2);
    }
}
