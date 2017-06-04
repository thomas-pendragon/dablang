#include "cvm.h"

void DabValue::dump(DabVM &vm, FILE *file) const
{
    (void)vm;
    static const char *types[] = {"INVA", "FIXN", "STRI", "BOOL", "NIL ", "SYMB", "CLAS", "OBJE"};
    fprintf(file, "%s ", types[data.type]);
    print(file, true);
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
    case TYPE_ARRAY:
        return CLASS_ARRAY;
        break;
    case TYPE_CLASS:
        return data.fixnum;
        break;
    case TYPE_OBJECT:
        return this->data.object->object->klass;
        break;
    default:
        fprintf(stderr, "Unknown data.type %d.\n", (int)data.type);
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

bool DabValue::is_a(DabVM &vm, const DabClass &klass) const
{
    return get_class(vm).is_subclass_of(vm, klass);
}

void DabValue::print(FILE *out, bool debug) const
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
        fprintf(out, "%s", class_name(*$VM).c_str());
        break;
    case TYPE_OBJECT:
        fprintf(out, "#%s", class_name(*$VM).c_str());
        break;
    case TYPE_ARRAY:
    {
        fprintf(out, "[");
        size_t i = 0;
        for (auto &item : array())
        {
            if (i)
                fprintf(out, ", ");
            item.print(out, debug);
            i++;
        }
        fprintf(out, "]");
    }
    break;
    default:
        fprintf(out, "?");
        break;
    }
}

std::vector<DabValue> &DabValue::array() const
{
    assert(data.type == TYPE_ARRAY);
    auto *obj = (DabArray *)data.object->object;
    return obj->array;
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

    DabBaseObject *object = nullptr;
    auto           type   = TYPE_OBJECT;
    if (data.fixnum == CLASS_ARRAY)
    {
        object = new DabArray;
        type   = TYPE_ARRAY;
    }
    else
    {
        object = new DabObject;
    }

    DabObjectProxy *proxy = new DabObjectProxy;
    proxy->object         = object;
    proxy->count_strong   = 1;
    proxy->object->klass  = this->data.fixnum;

    DabValue ret;
    ret.data.type   = type;
    ret.data.object = proxy;

    fprintf(stderr, "VM: proxy %p (strong %d): ! created\n", proxy, (int)proxy->count_strong);

    return ret;
}

DabValue DabValue::_get_instvar(DabVM &vm, const std::string &name)
{
    (void)vm;
    assert(this->data.type == TYPE_OBJECT);
    assert(this->data.object);

    if (!this->data.object->object)
    {
        return DabValue(nullptr);
    }

    auto  object   = (DabObject *)this->data.object->object;
    auto &instvars = object->instvars;

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
    ret.print(stderr);
    fprintf(stderr, "\n");
    return ret;
}

void DabValue::set_instvar(DabVM &vm, const std::string &name, const DabValue &value)
{
    (void)vm;
    assert(this->data.type == TYPE_OBJECT);
    assert(this->data.object);

    fprintf(stderr, "VM: proxy %p (strong %d): Set instvar <%s> to ", this->data.object,
            (int)this->data.object->count_strong, name.c_str());
    value.print(stderr);
    fprintf(stderr, "\n");

    if (!this->data.object->object)
    {
        return;
    }

    auto  object   = (DabObject *)this->data.object->object;
    auto &instvars = object->instvars;
    instvars[name] = value;
}

void DabValue::set_data(const DabValueData &other_data)
{
    data = other_data;
    if (data.type == TYPE_OBJECT || data.type == TYPE_ARRAY)
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
    if (this->data.type == TYPE_OBJECT || data.type == TYPE_ARRAY)
    {
        this->data.object->release(this);
    }
}

//

void DabObjectProxy::retain()
{
    count_strong += 1;
    fprintf(stderr, "VM: proxy %p (strong %d): + retained\n", this, (int)this->count_strong);
}

void DabObjectProxy::release(DabValue *value)
{
    count_strong -= 1;
    fprintf(stderr, "VM: proxy %p (strong %d): - released\n", this, (int)this->count_strong);
    if (count_strong == 0)
    {
        destroy(value);
    }
}

void DabObjectProxy::destroy(DabValue *value)
{
    (void)value;
    fprintf(stderr, "VM: proxy %p (strong %d): X destroy\n", this, (int)this->count_strong);
    delete object;
    delete this;
}

size_t DabValue::use_count() const
{
    if (data.object)
    {
        return data.object->count_strong;
    }
    else
    {
        return 65535;
    }
}
