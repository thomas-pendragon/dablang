#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <string.h>
#include <stdint.h>

// Prototype for the template function
int func_template(void *ptr) {
    printf("func_template called with ptr = %p\n", ptr);
    return 0;
}

// Function to load a 64-bit integer into machine code
void load_address(unsigned char *code_ptr, uintptr_t value) {
    for (int i = 0; i < 8; i++) {
        code_ptr[i] = (value >> (8 * i)) & 0xFF;
    }
}

// Function to create dynamically generated code
int (*create_dynamic_func(void *literal))(void) {
    // Get the address of func_template to be called by our machine code
    void *template_func_addr = (void *)&func_template;

    // Machine code that:
    // - Moves the 64-bit `literal` into the RDI register (the first argument in x86-64 calling convention)
    // - Calls func_template (which is at the address we provide)
    // - Returns from the function
    unsigned char code[27] = {
        0x48, 0xBF,                                 // mov rdi, imm64 (load the literal into RDI)
        0, 0, 0, 0, 0, 0, 0, 0,
        0x48, 0xB8,                                 // mov rax, imm64 (load the address of func_template into RAX)
        0, 0, 0, 0, 0, 0, 0, 0,
        0xFF, 0xD0,                                 // call rax (call the function whose address is in RAX)
        0xC3                                        // ret (return from the function)
    };

    load_address(&code[2], (uintptr_t)literal);
    load_address(&code[12], (uintptr_t)&func_template);

    // Allocate memory with rwx (read, write, execute) permissions
    void *mem = mmap(NULL, sizeof(code), PROT_READ | PROT_WRITE | PROT_EXEC,
                     MAP_PRIVATE | MAP_ANON, -1, 0);
    if (mem == MAP_FAILED) {
        perror("mmap");
        return NULL;
    }

    // Copy the machine code to the allocated memory
    memcpy(mem, code, sizeof(code));

    // Cast the memory to a function pointer and return it
    return (int (*)(void))mem;
}

int main() {
    // Literal to pass to the dynamically generated function
    void *hardcoded_ptr = (void *)0x12345678DEADBEEF;

    // Create the dynamic function with the literal
    int (*dynamic_func)(void) = create_dynamic_func(hardcoded_ptr);

    if (dynamic_func == NULL) {
        return 1;  // Failed to create dynamic function
    }

    // Execute the dynamically generated function
    dynamic_func();

    // Normally, we'd call `munmap` to free the memory, but in this case, 
    // the OS will reclaim it automatically when the program ends.
    return 0;
}
