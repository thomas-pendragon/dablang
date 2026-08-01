#include "../../src/cvm/string_intptr_storage.h"

#include <cassert>
#include <cstring>
#include <memory>
#include <string>

int main()
{
    std::weak_ptr<char>    released_storage;
    DabStringIntPtrStorage surviving_copy;

    {
        DabStringIntPtrStorage original(std::string("trusted-local-ffi"));
        released_storage = original.weak_owner();
        surviving_copy   = original;

        assert(original.get() == surviving_copy.get());
        assert(std::strcmp((const char *)surviving_copy.get(), "trusted-local-ffi") == 0);
        assert(original.use_count() == 2);
    }

    assert(!released_storage.expired());
    assert(std::strcmp((const char *)surviving_copy.get(), "trusted-local-ffi") == 0);

    surviving_copy.reset();
    assert(released_storage.expired());

    return 0;
}
