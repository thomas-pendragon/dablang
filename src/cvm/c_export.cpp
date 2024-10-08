#include "cvm.h"
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <string.h>
#include <stdint.h>

static void load_address(unsigned char *code_ptr, uintptr_t value)
{
    for (int i = 0; i < 8; i++)
    {
        code_ptr[i] = (value >> (8 * i)) & 0xFF;
    }
}

typedef int (*int_fun_handler_ptr)(void *);
typedef int (*int_fun_ptr)();

static int_fun_ptr create_dynamic_func(int_fun_handler_ptr func_template, void *literal)
{
    // Machine code that:
    // - Moves the 64-bit `literal` into the RDI register (the first argument in x86-64 calling convention)
    // - Calls func_template (which is at the address we provide)
    // - Returns from the function
    unsigned char code[23] = {
        0x48, 0xBF, // mov rdi, imm64 (load the literal into RDI)
        0, 0, 0, 0, 0, 0, 0, 0,
        0x48, 0xB8,                                 // mov rax, imm64 (load the address of func_template into RAX)
        0, 0, 0, 0, 0, 0, 0, 0,
        0xFF, 0xD0,                                 // call rax (call the function whose address is in RAX)
        0xC3                       // ret (return from the function)
    };

    load_address(&code[2], (uintptr_t)literal);
    load_address(&code[12], (uintptr_t)func_template);

    // Allocate memory with rwx (read, write, execute) permissions
    void *mem =
        mmap(NULL, sizeof(code), PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (mem == MAP_FAILED)
    {
        perror("mmap");
        return NULL;
    }

    // Copy the machine code to the allocated memory
    memcpy(mem, code, sizeof(code));

    // Cast the memory to a function pointer and return it
    return (int_fun_ptr)mem;
}

struct DabIntFunctionHandler
{
    DabValue method;
};

static int call_dab_int_function(void *ptr)
{
    fprintf(stderr, "func_template called with ptr = %p\n", ptr);
    auto castPtr     = (DabIntFunctionHandler *)ptr;
    auto method_name = castPtr->method.string();
    fprintf(stderr, "func_template called for method '%s'\n", method_name.c_str());
    // DabValue cinstcall(DabValue self, const std::string &name, std::vector<DabValue> args = {});
    auto dab_val = $VM->cinstcall(castPtr->method, "call");
    return dab_val.data.num_int32;
    // return 77;
}

void DabVM::kernel_c_export(dab_register_t out_reg, std::vector<dab_register_t> reglist)
{
    assert(reglist.size() == 1);

    DabValue method = register_get(reglist[0]);

    auto method_name = method.string();

    DabIntFunctionHandler *handler = new DabIntFunctionHandler;
    handler->method                = method;

    fprintf(stderr, "vm: c_export '%s'\n", method_name.c_str());

    fprintf(stderr, "test handler: %d\n", call_dab_int_function(handler));

    auto cfun = create_dynamic_func(call_dab_int_function, handler);

    fprintf(stderr, "vm: created func at ptr %p\n", cfun);
    auto q = cfun();
    fprintf(stderr, "vm: test call? [%d]\n", q);

    auto  symbol      = (dab_symbol_t)method.data.fixnum;
    auto &fun         = functions[symbol];
    fun.c_export      = true;
    fun.c_export_addr = (void *)cfun;

    register_set(out_reg, nullptr);
}
