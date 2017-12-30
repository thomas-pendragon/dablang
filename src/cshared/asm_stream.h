#pragma once

struct BaseReader
{
    std::vector<unsigned char> data;
    uint64_t &                 _position;

    BaseReader(uint64_t &position) : _position(position)
    {
    }

    uint64_t position() const
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

    virtual uint64_t raw_read(void *buffer, uint64_t size) = 0;
};

struct StdinReader : public BaseReader
{
    StdinReader(uint64_t &position) : BaseReader(position)
    {
    }

    virtual uint64_t raw_read(void *buffer, uint64_t size) override
    {
        return fread(buffer, 1, (size_t)size, stdin);
    }

    bool feof()
    {
        return ::feof(stdin);
    }
};
