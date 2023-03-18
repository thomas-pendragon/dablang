#include "cvm.h"

void Coverage::add_file(uint64_t hash, const std::string &filename)
{
    fprintf(stderr, "VM coverage: file %d - '%s'\n", (int)hash, filename.c_str());
    files[hash] = filename;
}

void Coverage::add_line(uint64_t hash, uint64_t line)
{
    fprintf(stderr, "VM coverage: line %d - %d\n", (int)hash, (int)line);
    lines[hash][line] += 1;
}

void Coverage::dump(FILE *out) const
{
    size_t i = 0;
    fprintf(out, "[");
    for (auto &file : files)
    {
        if (i++ > 0)
            fprintf(out, ",\n");
        fprintf(out, "{\"file\": \"%s\", \"hits\": [", file.second.c_str());
        auto  &data = lines.at(file.first);
        size_t j    = 0;
        for (auto &line : data)
        {
            if (j++ > 0)
            {
                fprintf(out, ", ");
            }
            fprintf(out, "{\"line\": %d, \"hits\": %d}", (int)line.first, (int)line.second);
        }
        fprintf(out, "]}");
    }
    fprintf(out, "]\n");
}
