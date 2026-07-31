#include <cstddef>

int main()
{
    volatile std::size_t offset = 1U;
    char *volatile buffer       = new char[1];
    buffer[offset]              = 42;
    delete[] buffer;
    return 0;
}
