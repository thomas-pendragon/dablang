#pragma once

#include <vector>

struct BaseAsmStream
{
    std::vector<unsigned char> data;
    size_t &                   _position;

    BaseAsmStream(size_t &position) : _position(position)
    {
    }

    size_t position() const
    {
        return _position;
    }

    void *read(size_t size = 1)
    {
        auto old_size = data.size();
        data.resize(old_size + size);
        auto buffer    = &data[old_size];
        auto real_size = fread(buffer, 1, size, stdin);
        if (!real_size)
            return nullptr;
        _position += size;
        return buffer;
    }

    template <typename T>
    T _read()
    {
        return *(T *)read(sizeof(T));
    }
};
