#include "cvm.h"

const DabFunction &DabClass::get_instance_function(const std::string &name) const
{
    return _get_function(false, name);
}

const DabFunction &DabClass::get_static_function(const std::string &name) const
{
    return _get_function(true, name);
}

const DabFunction &DabClass::_get_function(bool _static, const std::string &func_name) const
{
    auto &collection = _static ? static_functions : functions;
    auto  func_index = $VM->get_symbol_index(func_name);
    if (!collection.count(func_index))
    {
        if (index == superclass_index)
        {
            fprintf(stderr, "VM error: Unknown %sfunction <%s> in <%s>.\n",
                    _static ? "static " : "", func_name.c_str(), name.c_str());
            exit(1);
        }
        else
        {
            auto &superclass = $VM->get_class(superclass_index);
            return superclass._get_function(_static, func_name);
        }
    }
    return collection.at(func_index);
}

void DabClass::add_static_function(const std::string &name, dab_function_t body)
{
    DabFunction fun;
    fun.name    = name;
    fun.regular = false;
    fun.extra   = body;

    auto func_index = $VM->get_or_create_symbol_index(name);

    static_functions[func_index] = fun;
}

void DabClass::add_function(const std::string &name, dab_function_t body)
{
    DabFunction fun;
    fun.name    = name;
    fun.regular = false;
    fun.extra   = body;

    auto func_index = $VM->get_or_create_symbol_index(name);

    functions[func_index] = fun;
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

    auto &super = $VM->get_class(superclass_index);
    return super.is_subclass_of(klass);
}
