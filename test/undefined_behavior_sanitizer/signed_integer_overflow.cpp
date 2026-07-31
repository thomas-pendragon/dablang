#include <limits>

int main()
{
    volatile int maximum = std::numeric_limits<int>::max();
    volatile int one     = 1;
    return maximum + one;
}
