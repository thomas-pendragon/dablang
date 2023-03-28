#include "cvm.h"

void DabValue::dump(FILE *file) const
{
    if (!file)
    {
        file = $VM->options.console;
    }

    static const char *types[] = {"INVA", "FIXN", "BOOL", "NIL ", "CLAS", "OBJE",  "ARRY", "UIN8",
                                  "UI16", "UI32", "UI64", "INT8", "IN16", "IN32",  "IN64", "METH",
                                  "PTR*", "BYT*", "CSTR", "DSTR", "FLO",  "[LBL]", "BOX"};
    assert((int)data.type >= 0 && (int)data.type < (int)countof(types));
    fprintf(file, "%s ", types[data.type]);
    print(file, true);
}

void DabValue::dumpex(FILE *file) const
{
    dump(file);
    fprintf(file, "\n");
    if (data.type == TYPE_OBJECT)
    {
        auto objp = data.object;
        auto obj  = objp->object;
        if (obj)
        {
            fprintf(file, "at %p\n", obj);

            auto dd = dynamic_cast<DabObject *>(obj);
            if (dd)
            {
                for (auto i : dd->instvars)
                {
                    fprintf(file, "[%s]: ", $VM->get_symbol(i.first).c_str());
                    i.second.dump(file);
                    fprintf(file, "\n");
                }
            }
        }
    }
}

dab_class_t DabValue::class_index() const
{
    switch (data.type)
    {
    case TYPE_FIXNUM:
        return CLASS_FIXNUM;
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
        return (dab_class_t)data.fixnum;
        break;
    case TYPE_OBJECT:
        return (dab_class_t)this->data.object->object->klass;
        break;
    case TYPE_UINT8:
        return CLASS_UINT8;
        break;
    case TYPE_UINT16:
        return CLASS_UINT16;
        break;
    case TYPE_UINT32:
        return CLASS_UINT32;
        break;
    case TYPE_UINT64:
        return CLASS_UINT64;
        break;
    case TYPE_INT8:
        return CLASS_INT8;
        break;
    case TYPE_INT16:
        return CLASS_INT16;
        break;
    case TYPE_INT32:
        return CLASS_INT32;
        break;
    case TYPE_INT64:
        return CLASS_INT64;
        break;
    case TYPE_METHOD:
        return CLASS_METHOD;
        break;
        //    case TYPE_LOCALBLOCK:
        //        return CLASS_METHOD;
        //        break;
    case TYPE_INTPTR:
        return CLASS_INTPTR;
        break;
    case TYPE_BYTEBUFFER:
        return CLASS_BYTEBUFFER;
        break;
    case TYPE_LITERALSTRING:
        return CLASS_LITERALSTRING;
        break;
    case TYPE_DYNAMICSTRING:
        return CLASS_DYNAMICSTRING;
        break;
    case TYPE_FLOAT:
        return CLASS_FLOAT;
    default:
        char description[256];
        snprintf(description, sizeof(description), "Unknown data.type %d.\n", (int)data.type);
        throw DabRuntimeError(description);
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
    case TYPE_UINT16:
        snprintf(buffer, sizeof(buffer), "%" PRIu16, data.num_uint16);
        break;
    case TYPE_UINT32:
        snprintf(buffer, sizeof(buffer), "%" PRIu32, data.num_uint32);
        break;
    case TYPE_UINT64:
        snprintf(buffer, sizeof(buffer), "%" PRIu64, data.num_uint64);
        break;
    case TYPE_INT8:
        snprintf(buffer, sizeof(buffer), "%" PRId8, data.num_int8);
        break;
    case TYPE_INT16:
        snprintf(buffer, sizeof(buffer), "%" PRId16, data.num_int16);
        break;
    case TYPE_INT32:
        snprintf(buffer, sizeof(buffer), "%" PRId32, data.num_int32);
        break;
    case TYPE_INT64:
        snprintf(buffer, sizeof(buffer), "%" PRId64, data.num_int64);
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
    case TYPE_FLOAT:
        snprintf(buffer, sizeof(buffer), "%f", data.floatval);
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
    case TYPE_LITERALSTRING:
    case TYPE_DYNAMICSTRING:
    {
        use_ret = true;
        ret     = string();
        if (debug)
        {
            ret = "\"" + ret + "\"";
        }
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
    if (debug && is_object())
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

std::string DabValue::literal_string() const
{
    assert(data.type == TYPE_LITERALSTRING);
    auto *obj = (DabLiteralString *)data.object->object;
    return std::string(obj->pointer, (size_t)obj->length);
}

std::string DabValue::dynamic_string() const
{
    assert(data.type == TYPE_DYNAMICSTRING);
    auto *obj = (DabDynamicString *)data.object->object;
    return obj->value;
}

std::string DabValue::string() const
{
    bool dynamic = data.type == TYPE_DYNAMICSTRING;
    bool literal = data.type == TYPE_LITERALSTRING;
    bool method  = data.type == TYPE_METHOD;
    assert(literal || method || dynamic);
    if (method)
    {
        return $VM->get_symbol((dab_symbol_t)data.fixnum);
    }
    else if (dynamic)
    {
        return dynamic_string();
    }
    else
    {
        return literal_string();
    }
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
    case TYPE_BOOLEAN:
        return data.boolean;
    case TYPE_INTPTR:
        return data.intptr;
    case TYPE_NIL:
        return false;
    case TYPE_ARRAY:
        return array().size() > 0;
    case TYPE_LITERALSTRING:
        return literal_string().length();
    case TYPE_DYNAMICSTRING:
        return dynamic_string().length();
    case TYPE_FLOAT:
        return data.floatval != 0.0f;
    default:
        return true;
    }
}

void DabValue::setbox(DabValue new_value)
{
    assert(data.type == TYPE_BOX);

    auto proxy = this->data.object;
    auto box   = dynamic_cast<DabBox *>(proxy->object);

    box->value = new_value;
}

DabValue DabValue::box(DabValue base)
{
    DabValue ret;
    auto     box = new DabBox;
    box->value   = base;

    DabObjectProxy *proxy = new DabObjectProxy;
    proxy->object         = box;
    proxy->count_strong   = 1;
    //        proxy->object->klass  = this->data.fixnum;

    ret.data.type   = TYPE_BOX;
    ret.data.object = proxy;

    return ret;
}

DabValue DabValue::unbox(DabValue base)
{
    auto proxy = base.data.object;
    auto box   = dynamic_cast<DabBox *>(proxy->object);
    return box->value;
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
    else if (data.fixnum == CLASS_LITERALSTRING)
    {
        object = new DabLiteralString;
        type   = TYPE_LITERALSTRING;
    }
    else if (data.fixnum == CLASS_DYNAMICSTRING)
    {
        object = new DabDynamicString;
        type   = TYPE_DYNAMICSTRING;
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

    if ($VM->options.verbose)
    {
        fprintf(stderr, "vm: proxy %p A (strong %3d): ! created : ", proxy,
                (int)proxy->count_strong);
        ret.dump(stderr);
        fprintf(stderr, "\n");
    }

    return ret;
}

DabValue DabValue::allocate_dynstr(const char *str)
{
    DabValue klass = $VM->get_class(CLASS_DYNAMICSTRING);

    auto ret = klass.create_instance();

    auto *obj = (DabDynamicString *)ret.data.object->object;

    obj->value = str;
    return ret;
}

DabValue DabValue::_get_instvar(dab_symbol_t symbol)
{
    assert(this->data.type == TYPE_OBJECT);
    assert(this->data.object);

    if (!this->data.object->object)
    {
        return DabValue(nullptr);
    }

    auto  object   = (DabObject *)this->data.object->object;
    auto &instvars = object->instvars;

    if (!instvars.count(symbol))
    {
        return DabValue(nullptr);
    }
    return instvars[symbol];
}

DabValue DabValue::get_instvar(dab_symbol_t symbol)
{
    auto ret = _get_instvar(symbol);
    if ($VM->options.verbose)
    {
        auto name = $VM->get_symbol(symbol);

        fprintf(stderr, "vm: proxy %p (strong %d): Get instvar <%s> -> ", this->data.object,
                (int)this->data.object->count_strong, name.c_str());
        ret.print(stderr);
        fprintf(stderr, "\n");
    }
    return ret;
}

void DabValue::set_instvar(dab_symbol_t symbol, const DabValue &value)
{
    assert(this->data.type == TYPE_OBJECT);
    assert(this->data.object);

    if ($VM->options.verbose)
    {
        auto name = $VM->get_symbol(symbol);

        fprintf(stderr, "vm: proxy %p (strong %d): Set instvar <%s> to ", this->data.object,
                (int)this->data.object->count_strong, name.c_str());
        value.print(stderr);
        fprintf(stderr, "\n");
    }

    if (!this->data.object->object)
    {
        return;
    }

    auto  object     = (DabObject *)this->data.object->object;
    auto &instvars   = object->instvars;
    instvars[symbol] = value;
}

void DabValue::set_data(const DabValueData &other_data)
{
    data = other_data;
    if ($VM->options.autorelease)
    {
        retain();
    }
}

DabValue::DabValue(const DabValue &other)
{
    set_data(other.data);
    localblock = other.localblock;
}

DabValue &DabValue::operator=(const DabValue &other)
{
    set_data(other.data);
    localblock = other.localblock;
    return *this;
}

DabValue::~DabValue()
{
    if ($VM->options.autorelease)
    {
        release();
    }
}

void DabValue::release()
{
    if (is_object())
    {
        this->data.object->release(this);
        this->data.object = nullptr;
    }
    this->data.type        = TYPE_NIL;
    this->data._initialize = 0;
}

void DabValue::retain()
{
    if (is_object())
    {
        data.object->retain(this);
    }
}

//

void DabObjectProxy::retain(DabValue *value)
{
    (void)value;
    if (this->destroying)
        return;
    count_strong += 1;
    if ($VM->options.verbose)
    {
        fprintf(stderr, "vm: proxy %p B (strong %3d): + retained: ", this, (int)this->count_strong);
        value->dump(stderr);
        fprintf(stderr, "\n");
    }
}

void DabObjectProxy::release(DabValue *value)
{
    if (this->destroying)
        return;
    count_strong -= 1;
    if ($VM->options.verbose)
    {
        fprintf(stderr, "vm: proxy %p B (strong %3d): - released: ", this, (int)this->count_strong);
        value->dump(stderr);
        fprintf(stderr, "\n");
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
    if ($VM->options.verbose)
    {
        fprintf(stderr, "vm: proxy %p C (strong %3d): X destroy\n", this, (int)this->count_strong);
    }
    delete object;
    delete this;
}

size_t DabValue::use_count() const
{
    if (is_object())
    {
        return data.object->count_strong;
    }
    else
    {
        return 65535;
    }
}
