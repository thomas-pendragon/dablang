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

int main() {
    // Hardcoded pointer to pass to func_template
    void *hardcoded_ptr = (void *)0x12345678;

    // Get the address of func_template to be called by our machine code
    void *template_func_addr = (void *)&func_template;

    // Machine code that:
    // - Moves 0x12345678 into the RDI register (the first argument in x86-64 calling convention)
    // - Calls func_template (which is at the address we provided)
    // - Returns from the function
    unsigned char code[] = {
        0x48, 0xC7, 0xC7,                           // mov rdi, imm32 (load the argument into RDI)
        0x78, 0x56, 0x34, 0x12,                     // The immediate value (0x12345678) in little-endian
        0x48, 0xB8,                                 // mov rax, imm64 (load the address of func_template into RAX)
        (unsigned char)((uintptr_t)template_func_addr & 0xFF),
        (unsigned char)(((uintptr_t)template_func_addr >> 8) & 0xFF),
        (unsigned char)(((uintptr_t)template_func_addr >> 16) & 0xFF),
        (unsigned char)(((uintptr_t)template_func_addr >> 24) & 0xFF),
        (unsigned char)(((uintptr_t)template_func_addr >> 32) & 0xFF),
        (unsigned char)(((uintptr_t)template_func_addr >> 40) & 0xFF),
        (unsigned char)(((uintptr_t)template_func_addr >> 48) & 0xFF),
        (unsigned char)(((uintptr_t)template_func_addr >> 56) & 0xFF),
        0xFF, 0xD0,                                 // call rax (call the function whose address is in RAX)
        0xC3                                        // ret (return from the function)
    };

    // Allocate memory with rwx (read, write, execute) permissions
    void *mem = mmap(NULL, sizeof(code), PROT_READ | PROT_WRITE | PROT_EXEC,
                     MAP_PRIVATE | MAP_ANON, -1, 0);
    if (mem == MAP_FAILED) {
        perror("mmap");
        return 1;
    }

    // Copy the machine code to the allocated memory
    memcpy(mem, code, sizeof(code));

    // Cast the memory to a function pointer and call it
    int (*dynamic_func)(void) = (int (*)(void))mem;

    // Execute the dynamically generated function
    dynamic_func();

    // Clean up and free the memory
    if (munmap(mem, sizeof(code)) == -1) {
        perror("munmap");
        return 1;
    }

    return 0;
}
