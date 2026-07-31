#include <cstddef>

int main(int argc, char **argv)
{
    volatile std::size_t offset = argc > 1 ? 1U : 1U;
    volatile char       *buffer = new char[1];
    buffer[offset]              = 42;
    delete[] const_cast<char *>(buffer);
    return 0;
}
