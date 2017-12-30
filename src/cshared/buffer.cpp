#include "stream.h"

Buffer::Buffer()
{
}

Buffer::Buffer(const Buffer &other, uint64_t start, uint64_t length)
{
    this->data         = other.data + start;
    this->length       = length;
    this->_dont_delete = true;
}

Buffer::Buffer(const Buffer &other)
{
    this->length = other.length;
    if (other.data)
    {
        this->data = (byte *)malloc((size_t)this->length);
        memcpy(this->data, other.data, (size_t)this->length);
    }
}

Buffer::~Buffer()
{
    if (!_dont_delete)
    {
        free(this->data);
    }
}

Buffer &Buffer::operator=(const Buffer &other)
{
    delete[] this->data;
    this->length = other.length;
    if (other.data)
    {
        this->data = (byte *)malloc((size_t)this->length);
        memcpy(this->data, other.data, (size_t)this->length);
    }
    return *this;
}

void Buffer::resize(uint64_t new_length)
{
    byte *new_data = (byte *)malloc((size_t)new_length);
    if (data)
    {
        memcpy(new_data, this->data, min(this->length, new_length));
    }
    free(this->data);
    this->data   = new_data;
    this->length = new_length;
}

void Buffer::append(const byte *data, uint64_t data_length)
{
    const uint64_t old_length = this->length;
    const uint64_t new_length = old_length + data_length;
    assert(new_length > old_length);
    resize(new_length);
    memcpy(this->data + old_length, data, data_length);
}
