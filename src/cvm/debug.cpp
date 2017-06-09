#include "cvm.h"
#include "../cshared/disasm.h"

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
            fprintf(stderr, "   ::%s [%s]\n", fin.first.c_str(), fin.second.regular ? "Dab" : "C");
        }
        for (const auto &fin : it.second.functions)
        {
            fprintf(stderr, "    .%s [%s]\n", fin.first.c_str(), fin.second.regular ? "Dab" : "C");
        }
    }
}

void DabVM_debug::print_functions()
{
    for (auto it : vm.functions)
    {
        auto &fun = it.second;
        fprintf(stderr, " - %s: %s at %p\n", fun.name.c_str(), fun.regular ? "Dab" : "C",
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

void DabVM_debug::print_code()
{
    prepare_disasm();

    auto err_stream = stdout;

    auto ip = vm.ip();

    fprintf(err_stream, "IP = %d\n", (int)ip);

    auto it = find_if(disasm.begin(), disasm.end(),
                      [ip](const std::pair<size_t, std::string> &obj) { return obj.first == ip; });

    if (it == disasm.end())
        return;

    auto index = std::distance(disasm.begin(), it);

    for (int i = index - 2; i <= index + 2; i++)
    {
        if (i < 0 || i >= (int)disasm.size())
            continue;

        const auto &line = disasm[i];
        fprintf(err_stream, "%c %8ld: %s\n", line.first == ip ? '>' : ' ', line.first,
                line.second.c_str());
    }
}

struct InstructionsReader : public BaseReader
{
    DabVM &vm;
    InstructionsReader(DabVM &vm, size_t &position) : BaseReader(position), vm(vm)
    {
    }

    virtual size_t raw_read(void *buffer, size_t size) override
    {
        auto data       = vm.instructions.raw_base_data();
        auto length     = vm.instructions.raw_base_length();
        auto offset     = position();
        auto max_length = std::min(size, length - offset);

        memcpy(buffer, data + offset, max_length);

        return max_length;
    }
};

void DabVM_debug::prepare_disasm()
{
    if (has_disasm)
        return;

    has_disasm = true;

    size_t                              position = 0;
    InstructionsReader                  reader(vm, position);
    DisasmProcessor<InstructionsReader> processor(reader);

    processor.go(
        [this](size_t pos, std::string info) { disasm.push_back(std::make_pair(pos, info)); });
}

void DabVM::execute_debug(Stream &input)
{
    auto err_stream = stdout;

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
            fprintf(err_stream, "Help:\n");
            fprintf(err_stream, "help - print this\n");
            fprintf(err_stream, "[s]tep - run single instruction\n");
            fprintf(err_stream, "[r]egisters - show registers\n");
            fprintf(err_stream, "classes - print classes\n");
            fprintf(err_stream, "functions - print functions\n");
            fprintf(err_stream, "constants - dump constants\n");
            fprintf(err_stream, "stack - dump stack\n");
            fprintf(err_stream, "code - show current code\n");
            fprintf(err_stream, "run - run remaining instructions\n");
            fprintf(err_stream, "break [ip] - break at defined IP\n");
            fprintf(err_stream, "quit - quit\n");
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
        else if (cmd == "code")
        {
            debug.print_code();
        }
        else if (cmd == "quit")
        {
            exit(0);
        }
        else if (cmd == "run")
        {
            execute(input);
        }
        else if (cmd.substr(0, 6) == "break ")
        {
            int ip  = 0;
            int ret = sscanf(cmd.c_str(), "break %d", &ip);
            assert(ret == 1);
            fprintf(stdout, "debug: break at %d.\n", ip);
            breakpoints.insert(ip);
        }
        else
        {
            fprintf(stderr, "Unknown command, type <help> to get available commands.\n");
        }
    }
}
