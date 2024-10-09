#include <stdio.h>

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
        fprintf(stderr, "C FFI: running...\n");
        fprintf(stderr, "C FFI: running... fun = %p\n", fun);
        int res = fun();
        fprintf(stderr, "C FFI: running... fun = %p res = %d\n", fun, res);        
        return 5 * res;
    }

    typedef int (*ffi_fun_int_retint_type)(int);
    int ffi_fun_arg_test(ffi_fun_int_retint_type fun)
    {
        return 5 * fun(2);
    }
}
