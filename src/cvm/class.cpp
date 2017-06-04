#include "cvm.h"

const DabFunction &DabClass::get_function(const DabValue &klass, const std::string &name) const
{
    if (klass.data.type == TYPE_CLASS)
    {
        return get_static_function(klass, name);
    }
    return _get_function(false, klass, name);
}

const DabFunction &DabClass::get_static_function(const DabValue &   klass,
                                                 const std::string &name) const
{
    return _get_function(true, klass, name);
}

const DabFunction &DabClass::_get_function(bool _static, const DabValue &klass,
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
            auto &superclass = $VM->get_class(superclass_index);
            return superclass._get_function(_static, klass, name);
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

void DabClass::add_simple_function(const std::string &name, dab_simple_function_t body)
{
    add_function(name, [body](size_t n_args, size_t n_ret, void *blockaddr) {
        assert(blockaddr == 0);
        assert(n_args == 1);
        assert(n_ret == 1);
        auto self = $VM->stack.pop_value();
        auto ret  = body(self);
        $VM->stack.push_value(ret);
    });
}

bool DabClass::is_subclass_of(const DabClass &klass) const
{
    if (index == klass.index)
        return true;

    if (index == superclass_index)
        return false;

    auto super = $VM->get_class(superclass_index);
    return super.is_subclass_of(klass);
}
