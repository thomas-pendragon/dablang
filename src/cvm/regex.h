#pragma once

#include "cvm.h"

#include <string>
#include <vector>

struct DabRegex : public DabBaseObject
{
    std::string source;
    void       *compiled = nullptr;

    DabRegex();
    DabRegex(std::string source, void *compiled);
    virtual ~DabRegex();

    DabRegex(const DabRegex &)            = delete;
    DabRegex &operator=(const DabRegex &) = delete;
};

void     dab_regex_verify_engine();
DabValue dab_regex_create(const std::vector<DabValue> &arguments);
