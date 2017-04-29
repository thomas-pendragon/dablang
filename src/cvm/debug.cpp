#include "cvm.h"

struct DabVM_debug
{
    DabVM &vm;
    DabVM_debug(DabVM &vm) : vm(vm)
    {
    }
    void print_registers();
    void print_classes();
    void print_functions();
    void print_constants();
    void print_stack();
};

void DabVM_debug::print_registers()
{
    fprintf(stderr, "IP = %p (%d) Frame = %d\n", (void *)vm.ip(), (int)vm.ip(),
            (int)vm.frame_position);
}

void DabVM_debug::print_classes()
{
    for (const auto &it : vm.classes)
    {
        fprintf(stderr, " - 0x%04x %s (super = 0x%04x)\n", it.first, it.second.name.c_str(),
                it.second.superclass_index);
        for (const auto &fin : it.second.static_functions)
        {
            fprintf(stderr, "   ::%s\n", fin.first.c_str());
        }
        for (const auto &fin : it.second.functions)
        {
            fprintf(stderr, "    .%s\n", fin.first.c_str());
        }
    }
}

void DabVM_debug::print_functions()
{
    for (auto it : vm.functions)
    {
        auto &fun = it.second;
        fprintf(stderr, " - %s: %s at %p\n", fun.name.c_str(), fun.regular ? "regular" : "extra",
                (void *)fun.address);
    }
}

void DabVM_debug::print_constants()
{
    vm._dump("constants", vm.constants);
}

void DabVM_debug::print_stack()
{
    vm._dump("stack", vm.stack._data);
}

void DabVM::execute_debug(Stream &input)
{
    DabVM_debug debug(*this);
    while (!input.eof())
    {
        char rawcmd[2048];
        fprintf(stderr, "> ");
        fgets(rawcmd, sizeof(rawcmd), stdin);
        std::string cmd = rawcmd;

        cmd = cmd.substr(0, cmd.length() - 1);

        if (cmd == "help")
        {
            fprintf(stderr, "Help:\n");
            fprintf(stderr, "help - print this\n");
            fprintf(stderr, "[s]tep - run single instruction\n");
            fprintf(stderr, "[r]egisters - show registers\n");
            fprintf(stderr, "classes - print classes\n");
            fprintf(stderr, "functions - print functions\n");
            fprintf(stderr, "constants - dump constants\n");
            fprintf(stderr, "stack - dump stack\n");
        }
        else if (cmd == "step" || cmd == "s")
        {
            execute_single(input);
        }
        else if (cmd == "registers" || cmd == "r")
        {
            debug.print_registers();
        }
        else if (cmd == "classes")
        {
            debug.print_classes();
        }
        else if (cmd == "functions")
        {
            debug.print_functions();
        }
        else if (cmd == "constants")
        {
            debug.print_constants();
        }
        else if (cmd == "stack")
        {
            debug.print_stack();
        }
        else if (cmd == "quit")
        {
            exit(0);
        }
        else
        {
            fprintf(stderr, "Unknown command, type <help> to get available commands.\n");
        }
    }
}
