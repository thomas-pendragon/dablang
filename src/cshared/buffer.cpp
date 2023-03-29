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
        memcpy(new_data, this->data, (size_t)min(this->length, new_length));
    }
    free(this->data);
    this->data   = new_data;
    this->length = new_length;
}

void Buffer::append(const byte *new_data, uint64_t new_data_length)
{
    const uint64_t old_length = this->length;
    const uint64_t new_length = old_length + new_data_length;
    assert(new_length > old_length);
    resize(new_length);
    memcpy(this->data + old_length, new_data, (size_t)new_data_length);
}

void Buffer::dump(FILE *out)
{
    for (int i = 0; i < (int)length; i += 16)
    {
        fprintf(out, "%08x  ", (int)i);
        for (int j = 0; j < 16; j++)
        {
            auto p = i + j;
            if (p < (int)length)
            {
                fprintf(out, "%02x ", data[p]);
            }
            if (j == 7)
                fprintf(out, " ");
        }
        fprintf(out, "\n");
    }
}
