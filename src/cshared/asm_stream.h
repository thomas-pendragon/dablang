#pragma once

struct BaseReader
{
    std::vector<unsigned char> data;
    size_t &                   _position;

    BaseReader(size_t &position) : _position(position)
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
        auto real_size = raw_read(buffer, size);
        if (!real_size)
            return nullptr;
        _position += size;
        return buffer;
    }

    unsigned char operator[](size_t index) const
    {
        return data[index];
    }

    virtual size_t raw_read(void *buffer, size_t size) = 0;
};

struct StdinReader : public BaseReader
{
    StdinReader(size_t &position) : BaseReader(position)
    {
    }

    virtual size_t raw_read(void *buffer, size_t size) override
    {
        return fread(buffer, 1, size, stdin);
    }

    bool feof()
    {
        return ::feof(stdin);
    }
};
