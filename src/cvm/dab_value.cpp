#include "cvm.h"

void DabValue::dump(FILE *file) const
{
    static const char *types[] = {"INVA", "FIXN", "STRI", "BOOL", "NIL ", "SYMB", "CLAS", "OBJE",
                                  "ARRY", "UIN8", "UI32", "UI64", "IN32", "METH", "PTR*", "BYT*"};
    assert((int)data.type >= 0 && (int)data.type < (int)countof(types));
    fprintf(file, "%s ", types[data.type]);
    print(file, true);
}

int DabValue::class_index() const
{
    switch (data.type)
    {
    case TYPE_FIXNUM:
        return CLASS_FIXNUM;
        break;
    case TYPE_STRING:
        return CLASS_STRING;
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
    case TYPE_UINT8:
        return CLASS_UINT8;
        break;
    case TYPE_UINT32:
        return CLASS_UINT32;
        break;
    case TYPE_UINT64:
        return CLASS_UINT64;
        break;
    case TYPE_INT32:
        return CLASS_INT32;
        break;
    case TYPE_METHOD:
        return CLASS_METHOD;
        break;
    case TYPE_INTPTR:
        return CLASS_INTPTR;
        break;
    case TYPE_BYTEBUFFER:
        return CLASS_BYTEBUFFER;
        break;
    default:
        fprintf(stderr, "Unknown data.type %d.\n", (int)data.type);
        assert(false);
        break;
    }
}

std::string DabValue::class_name() const
{
    return get_class().name;
}

DabClass &DabValue::get_class() const
{
    return $VM->get_class(class_index());
}

bool DabValue::is_a(const DabClass &klass) const
{
    return get_class().is_subclass_of(klass);
}

void DabValue::print(FILE *out, bool debug) const
{
    fprintf(out, "%s", print_value(debug).c_str());
}

std::string DabValue::print_value(bool debug) const
{
    char        buffer[32] = {0};
    std::string ret;
    bool        use_ret = false;
    switch (data.type)
    {
    case TYPE_FIXNUM:
        snprintf(buffer, sizeof(buffer), "%" PRId64, data.fixnum);
        break;
    case TYPE_UINT8:
        snprintf(buffer, sizeof(buffer), "%" PRIu8, data.num_uint8);
        break;
    case TYPE_UINT32:
        snprintf(buffer, sizeof(buffer), "%" PRIu32, data.num_uint32);
        break;
    case TYPE_UINT64:
        snprintf(buffer, sizeof(buffer), "%" PRIu64, data.num_uint64);
        break;
    case TYPE_INT32:
        snprintf(buffer, sizeof(buffer), "%" PRId32, data.num_int32);
        break;
    case TYPE_STRING:
    {
        use_ret = true;
        ret     = data.string;
        if (debug)
        {
            ret = "\"" + ret + "\"";
        }
    }
    break;
    case TYPE_SYMBOL:
        snprintf(buffer, sizeof(buffer), ":%s", data.string.c_str());
        break;
    case TYPE_BOOLEAN:
        snprintf(buffer, sizeof(buffer), "%s", data.boolean ? "true" : "false");
        break;
    case TYPE_NIL:
        snprintf(buffer, sizeof(buffer), "nil");
        break;
    case TYPE_CLASS:
        snprintf(buffer, sizeof(buffer), "%s", class_name().c_str());
        break;
    case TYPE_OBJECT:
        snprintf(buffer, sizeof(buffer), "#%s", class_name().c_str());
        break;
    case TYPE_INTPTR:
        snprintf(buffer, sizeof(buffer), "%p", data.intptr);
        break;
    case TYPE_ARRAY:
    {
        use_ret  = true;
        ret      = "[";
        size_t i = 0;
        for (auto &item : array())
        {
            if (i)
                ret += ", ";
            ret += item.print_value(debug);
            i++;
        }
        ret += "]";
    }
    break;
    default:
        snprintf(buffer, sizeof(buffer), "?");
        break;
    }
    if (!use_ret)
    {
        ret = buffer;
    }
    if (debug && data.object)
    {
        char extra[64] = {0};
        snprintf(extra, sizeof(extra), " [%d strong]", (int)data.object->count_strong);
        ret += extra;
    }
    return ret;
}

std::vector<DabValue> &DabValue::array() const
{
    assert(data.type == TYPE_ARRAY);
    auto *obj = (DabArray *)data.object->object;
    return obj->array;
}

std::vector<uint8_t> &DabValue::bytebuffer() const
{
    assert(data.type == TYPE_BYTEBUFFER);
    auto *obj = (DabByteBuffer *)data.object->object;
    return obj->bytebuffer;
}

bool DabValue::truthy() const
{
    switch (data.type)
    {
    case TYPE_FIXNUM:
        return data.fixnum;
    case TYPE_UINT8:
        return data.num_uint8;
    case TYPE_UINT32:
        return data.num_uint32;
    case TYPE_UINT64:
        return data.num_uint64;
    case TYPE_INT32:
        return data.num_int32;
    case TYPE_STRING:
        return data.string.length();
        break;
    case TYPE_BOOLEAN:
        return data.boolean;
    case TYPE_INTPTR:
        return data.intptr;
    case TYPE_NIL:
        return false;
    case TYPE_ARRAY:
        return array().size() > 0;
    default:
        return true;
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
    else if (data.fixnum == CLASS_BYTEBUFFER)
    {
        object = new DabByteBuffer;
        type   = TYPE_BYTEBUFFER;
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

    if ($VM->verbose)
    {
        fprintf(stderr, "vm: proxy %p (strong %d): ! created\n", proxy, (int)proxy->count_strong);
    }

    return ret;
}

DabValue DabValue::_get_instvar(const std::string &name)
{
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

DabValue DabValue::get_instvar(const std::string &name)
{
    auto ret = _get_instvar(name);
    if ($VM->verbose)
    {
        fprintf(stderr, "vm: proxy %p (strong %d): Get instvar <%s> -> ", this->data.object,
                (int)this->data.object->count_strong, name.c_str());
        ret.print(stderr);
        fprintf(stderr, "\n");
    }
    return ret;
}

void DabValue::set_instvar(const std::string &name, const DabValue &value)
{
    assert(this->data.type == TYPE_OBJECT);
    assert(this->data.object);

    if ($VM->verbose)
    {
        fprintf(stderr, "vm: proxy %p (strong %d): Set instvar <%s> to ", this->data.object,
                (int)this->data.object->count_strong, name.c_str());
        value.print(stderr);
        fprintf(stderr, "\n");
    }

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
    if ($VM->autorelease)
    {
        retain();
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
    if ($VM->autorelease)
    {
        release();
    }
}

void DabValue::release()
{
    if (this->data.type == TYPE_OBJECT || data.type == TYPE_ARRAY)
    {
        this->data.object->release(this);
        this->data.object = nullptr;
    }
    this->data.type = TYPE_NIL;
}

void DabValue::retain()
{
    if (data.type == TYPE_OBJECT || data.type == TYPE_ARRAY)
    {
        data.object->retain();
    }
}

//

void DabObjectProxy::retain()
{
    if (this->destroying)
        return;
    count_strong += 1;
    if ($VM->verbose)
    {
        fprintf(stderr, "vm: proxy %p (strong %d): + retained\n", this, (int)this->count_strong);
    }
}

void DabObjectProxy::release(DabValue *value)
{
    if (this->destroying)
        return;
    count_strong -= 1;
    if ($VM->verbose)
    {
        fprintf(stderr, "vm: proxy %p (strong %d): - released\n", this, (int)this->count_strong);
    }
    if (count_strong == 0)
    {
        destroy(value);
    }
}

void DabObjectProxy::destroy(DabValue *value)
{
    (void)value;
    this->destroying = true;
    fprintf(stderr, "vm: proxy %p (strong %d): X destroy\n", this, (int)this->count_strong);
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
