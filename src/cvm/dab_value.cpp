#include "cvm.h"

void DabValue::dump(DabVM &vm) const
{
    static const char *kinds[] = {"INVAL", "PrvIP", "PrvSP", "nArgs", "nVars",
                                  "RETVL", "CONST", "VARIA", "STACK", "self "};
    static const char *types[] = {"INVA", "FIXN", "STRI", "BOOL", "NIL ", "SYMB", "CLAS", "OBJE"};
    fprintf(stderr, "%s %s ", kinds[data.kind], types[data.type]);
    print(vm, stderr, true);
}

int DabValue::class_index() const
{
    switch (data.type)
    {
    case TYPE_FIXNUM:
        return data.is_constant ? CLASS_LITERALFIXNUM : CLASS_FIXNUM;
        break;
    case TYPE_STRING:
        return data.is_constant ? CLASS_LITERALSTRING : CLASS_STRING;
        break;
    case TYPE_SYMBOL:
        return CLASS_INT_SYMBOL;
        break;
    case TYPE_BOOLEAN:
        return CLASS_BOOLEAN;
        break;
    case TYPE_NIL:
        return CLASS_NILCLASS;
        break;
    case TYPE_CLASS:
        return data.fixnum;
        break;
    case TYPE_OBJECT:
        return this->data.object->object->klass;
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
    switch (data.type)
    {
    case TYPE_FIXNUM:
        fprintf(out, "%zd", data.fixnum);
        break;
    case TYPE_STRING:
        fprintf(out, debug ? "\"%s\"" : "%s", data.string.c_str());
        break;
    case TYPE_SYMBOL:
        fprintf(out, ":%s", data.string.c_str());
        break;
    case TYPE_BOOLEAN:
        fprintf(out, "%s", data.boolean ? "true" : "false");
        break;
    case TYPE_NIL:
        fprintf(out, "nil");
        break;
    case TYPE_CLASS:
        fprintf(out, "%s", class_name(vm).c_str());
        break;
    case TYPE_OBJECT:
        fprintf(out, "#%s", class_name(vm).c_str());
        break;
    default:
        fprintf(out, "?");
        break;
    }
}

bool DabValue::truthy() const
{
    switch (data.type)
    {
    case TYPE_FIXNUM:
        return data.fixnum;
    case TYPE_STRING:
        return data.string.length();
        break;
    case TYPE_BOOLEAN:
        return data.boolean;
        break;
    case TYPE_NIL:
        return false;
        break;
    default:
        return true;
        break;
    }
}

DabValue DabValue::create_instance() const
{
    assert(data.type == TYPE_CLASS);

    DabObjectProxy *proxy = new DabObjectProxy;
    proxy->object         = new DabObject;
    proxy->count_strong   = 1;
    proxy->object->klass  = this->data.fixnum;

    DabValue ret;
    ret.data.type   = TYPE_OBJECT;
    ret.data.object = proxy;

    fprintf(stderr, "VM: proxy %p (strong %d): ! created\n", proxy, (int)proxy->count_strong);

    return ret;
}

DabValue DabValue::_get_instvar(DabVM &vm, const std::string &name)
{
    assert(this->data.type == TYPE_OBJECT);
    assert(this->data.object);

    if (!this->data.object->object)
    {
        return DabValue(nullptr);
    }

    auto &instvars = this->data.object->object->instvars;

    if (!instvars.count(name))
    {
        return DabValue(nullptr);
    }
    return instvars[name];
}

DabValue DabValue::get_instvar(DabVM &vm, const std::string &name)
{
    auto ret = _get_instvar(vm, name);
    fprintf(stderr, "VM: proxy %p (strong %d): Get instvar <%s> -> ", this->data.object,
            (int)this->data.object->count_strong, name.c_str());
    ret.print(vm, stderr);
    fprintf(stderr, "\n");
    return ret;
}

void DabValue::set_instvar(DabVM &vm, const std::string &name, const DabValue &value)
{
    assert(this->data.type == TYPE_OBJECT);
    assert(this->data.object);

    fprintf(stderr, "VM: proxy %p (strong %d): Set instvar <%s> to ", this->data.object,
            (int)this->data.object->count_strong, name.c_str());
    value.print(vm, stderr);
    fprintf(stderr, "\n");

    if (!this->data.object->object)
    {
        return;
    }

    auto &instvars = this->data.object->object->instvars;
    instvars[name] = value;
}

void DabValue::set_data(const DabValueData &other_data)
{
    data = other_data;
    if (data.type == TYPE_OBJECT)
    {
        data.object->retain();
    }
}

DabValue::DabValue(const DabValue &other)
{
    set_data(other.data);
}

DabValue &DabValue::operator=(const DabValue &other)
{
    set_data(other.data);
    return *this;
}

DabValue::~DabValue()
{
    if (this->data.type == TYPE_OBJECT)
    {
        this->data.object->release();
    }
}

//

void DabObjectProxy::retain()
{
    count_strong += 1;
    fprintf(stderr, "VM: proxy %p (strong %d): + retained\n", this, (int)this->count_strong);
}

void DabObjectProxy::release()
{
    count_strong -= 1;
    fprintf(stderr, "VM: proxy %p (strong %d): - released\n", this, (int)this->count_strong);
    if (count_strong == 0)
    {
        fprintf(stderr, "VM: proxy %p (strong %d): X destroy\n", this, (int)this->count_strong);
        delete object;
        delete this;
    }
}
