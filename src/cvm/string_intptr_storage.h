#pragma once

#include <cstring>
#include <memory>
#include <string>

class DabStringIntPtrStorage
{
  public:
    DabStringIntPtrStorage()
    {
    }

    explicit DabStringIntPtrStorage(const std::string &value)
        : storage(new char[value.size() + 1], std::default_delete<char[]>())
    {
        std::memcpy(storage.get(), value.c_str(), value.size() + 1);
    }

    void *get() const
    {
        return storage.get();
    }

    long use_count() const
    {
        return storage.use_count();
    }

    std::weak_ptr<char> weak_owner() const
    {
        return storage;
    }

    void reset()
    {
        storage.reset();
    }

  private:
    std::shared_ptr<char> storage;
};
