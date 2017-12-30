#include "cvm.h"
#include "../cshared/disasm.h"

void DabVM_debug::print_registers()
{
    fprintf(stderr, "IP = %p (%d)\n", (void *)vm.ip(), (int)vm.ip());
}

void DabVM_debug::print_ssa_registers()
{
    auto err_stream = $VM->options.output;
    fprintf(err_stream, "Registers:\n");
    size_t index = 0;
    for (const auto &reg : vm._registers)
    {
        fprintf(err_stream, "R%zu: ", index);
        reg.dump(err_stream);
        fprintf(err_stream, "\n");
    }
}

void DabVM_debug::print_classes()
{
    for (const auto &it : vm.classes)
    {
        fprintf(stderr, " - 0x%04x %s (super = 0x%04x)\n", it.first, it.second.name.c_str(),
                it.second.superclass_index);
        for (const auto &fin : it.second.static_functions)
        {
            fprintf(stderr, "   ::%s [%s]\n", $VM->get_symbol(fin.first).c_str(),
                    fin.second.regular ? "Dab" : "C");
        }
        for (const auto &fin : it.second.functions)
        {
            fprintf(stderr, "    .%s [%s]\n", $VM->get_symbol(fin.first).c_str(),
                    fin.second.regular ? "Dab" : "C");
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
    auto output = $VM->options.output;
    fprintf(output, "symbols:\n");
    size_t i = 0;
    for (const auto &symbol : $VM->symbols)
    {
        fprintf(output, "%d: %s\n", (int)i, symbol.c_str());
        i++;
    }
}

void DabVM_debug::print_stack()
{
}

void DabVM_debug::print_code(bool current_only)
{
    prepare_disasm();

    auto err_stream = $VM->options.output;

    auto ip = vm.ip();

    fprintf(err_stream, "IP = %d\n", (int)ip);

    auto it = find_if(disasm.begin(), disasm.end(),
                      [ip](const std::pair<size_t, std::string> &obj) { return obj.first == ip; });

    if (it == disasm.end())
        return;

    auto index = std::distance(disasm.begin(), it);

    long start = current_only ? (index - 2) : 0;
    long end   = current_only ? (index + 3) : disasm.size();

    for (long i = start; i < end; i++)
    {
        if (i < 0 || i >= (int)disasm.size())
            continue;

        const auto &line = disasm[i];
        fprintf(err_stream, "%c %8" PRIu64 ": %s\n", line.first == ip ? '>' : ' ', line.first,
                line.second.c_str());
    }
}

struct InstructionsReader : public BaseReader
{
    DabVM &vm;

    const byte *_data;
    uint64_t    _length;

    uint64_t start_position = 0;

    InstructionsReader(DabVM &vm, size_t &position) : BaseReader(position), vm(vm)
    {
        _data   = vm.instructions.raw_base_data();
        _length = vm.instructions.raw_base_length();

        BinSection code_section;
        bool       has_code = false;

        for (auto &section : vm.sections)
        {
            if (std::string(section.name) == "code")
            {
                code_section = section;
                has_code     = true;
                break;
            }
        }

        if (!has_code)
            throw "no code?";

        start_position = code_section.pos;

        _data += start_position;
        _length = code_section.length;
    }

    virtual size_t raw_read(void *buffer, size_t size) override
    {
        auto data       = _data;
        auto length     = _length;
        auto offset     = position();
        auto max_length = std::min(size, length - offset);

        memcpy(buffer, data + offset, max_length);

        return max_length;
    }

    bool feof()
    {
        return false;
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

    processor.go([this, reader](size_t pos, std::string info) {
        disasm.push_back(std::make_pair(pos + reader.start_position, info));
    });
}

void DabVM::execute_debug(Stream &input)
{
    auto err_stream = options.output;

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
            fprintf(err_stream, "allcode - show all code\n");
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
        else if (cmd == "ip")
        {
            fprintf(err_stream, "IP = %zu\n", ip());
        }
        else if (cmd == "code")
        {
            debug.print_code(true);
        }
        else if (cmd == "allcode")
        {
            debug.print_code(false);
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
            fprintf(err_stream, "debug: break at %d.\n", ip);
            breakpoints.insert(ip);
        }
        else if (cmd == "ssaregs")
        {
            debug.print_ssa_registers();
        }
        else
        {
            fprintf(stderr, "Unknown command, type <help> to get available commands.\n");
        }
    }
}
