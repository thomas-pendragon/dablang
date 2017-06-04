#include "cvm.h"

const DabFunction &DabClass::get_function(DabVM &vm, const DabValue &klass,
                                          const std::string &name) const
{
    if (klass.data.type == TYPE_CLASS)
    {
        return get_static_function(klass, name);
    }
    return _get_function(false, vm, klass, name);
}

const DabFunction &DabClass::get_static_function(const DabValue &   klass,
                                                 const std::string &name) const
{
    return _get_function(true, *$VM, klass, name);
}

const DabFunction &DabClass::_get_function(bool _static, DabVM &vm, const DabValue &klass,
                                           const std::string &name) const
{
    auto &collection = _static ? static_functions : functions;
    if (!collection.count(name))
    {
        if (index == superclass_index)
        {
            fprintf(stderr, "VM error: Unknown %sfunction <%s> in <%s>.\n",
                    _static ? "static " : "", name.c_str(), klass.class_name().c_str());
            exit(1);
        }
        else
        {
            auto &superclass = vm.get_class(superclass_index);
            return superclass._get_function(_static, vm, klass, name);
        }
    }
    return collection.at(name);
}

void DabClass::add_static_function(const std::string &name, dab_function_t body)
{
    DabFunction fun;
    fun.name               = name;
    fun.regular            = false;
    fun.extra              = body;
    static_functions[name] = fun;
}

void DabClass::add_function(const std::string &name, dab_function_t body)
{
    DabFunction fun;
    fun.name        = name;
    fun.regular     = false;
    fun.extra       = body;
    functions[name] = fun;
}

void DabClass::add_simple_function(DabVM &vm, const std::string &name, dab_simple_function_t body)
{
    add_function(name, [&vm, body](size_t n_args, size_t n_ret, void *blockaddr) {
        assert(blockaddr == 0);
        assert(n_args == 1);
        assert(n_ret == 1);
        auto self = vm.stack.pop_value();
        auto ret  = body(self);
        vm.stack.push_value(ret);
    });
}

bool DabClass::is_subclass_of(DabVM &vm, const DabClass &klass) const
{
    if (index == klass.index)
        return true;

    if (index == superclass_index)
        return false;

    auto super = vm.get_class(superclass_index);
    return super.is_subclass_of(vm, klass);
}
