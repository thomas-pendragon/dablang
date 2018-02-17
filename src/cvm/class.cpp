#include "cvm.h"

const DabFunction &DabClass::get_instance_function(dab_symbol_t symbol) const
{
    return _get_function(false, symbol, *this);
}

const DabFunction &DabClass::get_static_function(dab_symbol_t symbol) const
{
    return _get_function(true, symbol, *this);
}

const DabFunction &DabClass::_get_function(bool _static, dab_symbol_t symbol,
                                           const DabClass &base_class) const
{
    auto &collection = _static ? static_functions : functions;

    if (!collection.count(symbol))
    {
        if (index == superclass_index)
        {
            fprintf(stderr, "VM error: Unknown %sfunction <%s> in <%s>.\n",
                    _static ? "static " : "", $VM->get_symbol(symbol).c_str(),
                    base_class.name.c_str());
            exit(1);
        }
        else
        {
            auto &superclass = $VM->get_class(superclass_index);
            return superclass._get_function(_static, symbol, base_class);
        }
    }
    return collection.at(symbol);
}

void DabClass::_add_reg_function(bool is_static, const std::string &func_name,
                                 dab_function_reg_t body)
{
    auto &collection = is_static ? static_functions : functions;

    DabFunction fun;
    fun.name      = func_name;
    fun.regular   = false;
    fun.extra_reg = body;

    auto symbol = $VM->get_or_create_symbol_index(func_name);

    collection[symbol] = fun;
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
