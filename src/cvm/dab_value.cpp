#include "cvm.h"

void DabValue::dump(DabVM &vm) const
{
    static const char *kinds[] = {"INVAL", "PrvIP", "PrvSP", "nArgs", "nVars",
                                  "RETVL", "CONST", "VARIA", "STACK"};
    static const char *types[] = {"INVA", "FIXN", "STRI", "BOOL", "NIL ", "SYMB", "CLAS", "OBJE"};
    fprintf(stderr, "%s %s ", kinds[kind], types[type]);
    print(vm, stderr, true);
}

int DabValue::class_index() const
{
    switch (type)
    {
    case TYPE_FIXNUM:
        return is_constant ? CLASS_LITERALFIXNUM : CLASS_FIXNUM;
        break;
    case TYPE_STRING:
        return is_constant ? CLASS_LITERALSTRING : CLASS_STRING;
        break;
    case TYPE_SYMBOL:
        return CLASS_INT_SYMBOL;
        break;
    case TYPE_BOOLEAN:
        return CLASS_LITERALBOOLEAN;
        break;
    case TYPE_NIL:
        return CLASS_NILCLASS;
        break;
    case TYPE_CLASS:
        return fixnum;
        break;
    case TYPE_OBJECT:
        return fixnum;
        break;
    default:
        assert(false);
        break;
    }
}

std::string DabValue::class_name(DabVM &vm) const
{
    return get_class(vm).name;
}

DabClass &DabValue::get_class(DabVM &vm) const
{
    return vm.get_class(class_index());
}

void DabValue::print(DabVM &vm, FILE *out, bool debug) const
{
    switch (type)
    {
    case TYPE_FIXNUM:
        fprintf(out, "%zd", fixnum);
        break;
    case TYPE_STRING:
        fprintf(out, debug ? "\"%s\"" : "%s", string.c_str());
        break;
    case TYPE_SYMBOL:
        fprintf(out, ":%s", string.c_str());
        break;
    case TYPE_BOOLEAN:
        fprintf(out, "%s", boolean ? "true" : "false");
        break;
    case TYPE_NIL:
        fprintf(out, "nil");
        break;
    case TYPE_CLASS:
        fprintf(out, "%s", vm.classes[fixnum].name.c_str());
        break;
    case TYPE_OBJECT:
        if (fixnum == CLASS_STRING)
            fprintf(out, "");
        else
            fprintf(out, "#%s", vm.classes[fixnum].name.c_str());
        break;
    default:
        fprintf(out, "?");
        break;
    }
}

bool DabValue::truthy() const
{
    switch (type)
    {
    case TYPE_FIXNUM:
        return fixnum;
    case TYPE_STRING:
        return string.length();
        break;
    case TYPE_SYMBOL:
        return true;
        break;
    case TYPE_BOOLEAN:
        return boolean;
        break;
    case TYPE_NIL:
        return false;
        break;
    default:
        return false;
        break;
    }
}

DabValue DabValue::create_instance() const
{
    assert(type == TYPE_CLASS);
    auto copy = *this;
    copy.type = TYPE_OBJECT;
    return copy;
}
