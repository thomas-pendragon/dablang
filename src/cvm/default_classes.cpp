#include "cvm.h"

#include "defaults_shared.h"

DabClass &DabVM::define_builtin_class(const std::string &name, dab_class_t class_index,
                                      dab_class_t superclass_index)
{
    DabClass klass;
    klass.index            = class_index;
    klass.name             = name;
    klass.builtin          = true;
    klass.superclass_index = superclass_index;
    classes[class_index]   = klass;
    return classes[class_index];
}

void DabVM::predefine_default_classes()
{
    fprintf(stderr, "vm: predefine default classes\n");

    define_builtin_class("Object", CLASS_OBJECT);
    define_builtin_class("String", CLASS_STRING);
    define_builtin_class("Fixnum", CLASS_FIXNUM);
    define_builtin_class("Boolean", CLASS_BOOLEAN);
    define_builtin_class("NilClass", CLASS_NILCLASS);
    define_builtin_class("Array", CLASS_ARRAY);
    define_builtin_class("Uint8", CLASS_UINT8, CLASS_FIXNUM);
    define_builtin_class("Uint16", CLASS_UINT16, CLASS_FIXNUM);
    define_builtin_class("Uint32", CLASS_UINT32, CLASS_FIXNUM);
    define_builtin_class("Uint64", CLASS_UINT64, CLASS_FIXNUM);
    define_builtin_class("Int8", CLASS_INT8, CLASS_FIXNUM);
    define_builtin_class("Int16", CLASS_INT16, CLASS_FIXNUM);
    define_builtin_class("Int32", CLASS_INT32, CLASS_FIXNUM);
    define_builtin_class("Int64", CLASS_INT64, CLASS_FIXNUM);
    define_builtin_class("Method", CLASS_METHOD);
    define_builtin_class("IntPtr", CLASS_INTPTR);
    define_builtin_class("ByteBuffer", CLASS_BYTEBUFFER);
    define_builtin_class("LiteralString", CLASS_LITERALSTRING, CLASS_STRING);
    define_builtin_class("DynamicString", CLASS_DYNAMICSTRING, CLASS_STRING);
    define_builtin_class("Float", CLASS_FLOAT);
}


static char encoding_table[] = {'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H',
                                'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P',
                                'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X',
                                'Y', 'Z', 'a', 'b', 'c', 'd', 'e', 'f',
                                'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n',
                                'o', 'p', 'q', 'r', 's', 't', 'u', 'v',
                                'w', 'x', 'y', 'z', '0', '1', '2', '3',
                                '4', '5', '6', '7', '8', '9', '+', '/'};
static char *decoding_table = NULL;
// static int mod_table[] = {0, 2, 1};

static void build_decoding_table() {
    decoding_table =(char*) malloc(256);

    for (int i = 0; i < 64; i++)
        decoding_table[(unsigned char) encoding_table[i]] = i;
}

static unsigned char *base64_decode(const char *data,
                             size_t input_length,
                             size_t *output_length) {

    if (decoding_table == NULL) build_decoding_table();

    if (input_length % 4 != 0) return NULL;

    *output_length = input_length / 4 * 3;
    if (data[input_length - 1] == '=') (*output_length)--;
    if (data[input_length - 2] == '=') (*output_length)--;

    unsigned char *decoded_data =(unsigned char *) malloc(*output_length);
    if (decoded_data == NULL) return NULL;

    for (size_t i = 0, j = 0; i < input_length;) {

        uint32_t sextet_a = data[i] == '=' ? 0 & i++ : decoding_table[(int)data[i++]];
        uint32_t sextet_b = data[i] == '=' ? 0 & i++ : decoding_table[(int)data[i++]];
        uint32_t sextet_c = data[i] == '=' ? 0 & i++ : decoding_table[(int)data[i++]];
        uint32_t sextet_d = data[i] == '=' ? 0 & i++ : decoding_table[(int)data[i++]];

        uint32_t triple = (sextet_a << 3 * 6)
        + (sextet_b << 2 * 6)
        + (sextet_c << 1 * 6)
        + (sextet_d << 0 * 6);

        if (j < *output_length) decoded_data[j++] = (triple >> 2 * 8) & 0xFF;
        if (j < *output_length) decoded_data[j++] = (triple >> 1 * 8) & 0xFF;
        if (j < *output_length) decoded_data[j++] = (triple >> 0 * 8) & 0xFF;
    }

    return decoded_data;
}

void DabVM::define_default_classes()
{
    fprintf(stderr, "vm: define default classes\n");

    auto &object_class = get_class(CLASS_OBJECT);
    object_class.add_static_reg_function("new", [this](DabValue self, std::vector<DabValue> args) {
        auto arg = self;
        assert(arg.data.type == TYPE_CLASS);
        auto instance = arg.create_instance();
        cinstcall(instance, "__construct", args);
        return instance;
    });
    object_class.add_reg_function(
        "class", [](DabValue self, std::vector<DabValue>) { return self.get_class(); });
    object_class.add_reg_function("to_s", [](DabValue self, std::vector<DabValue> args) {
        assert(args.size() == 0);
        return self.print_value();
    });
    object_class.add_reg_function("__construct", [](DabValue, std::vector<DabValue> args) {
        assert(args.size() == 0);
        return nullptr;
    });
    object_class.add_reg_function("__destruct", [](DabValue, std::vector<DabValue> args) {
        assert(args.size() == 0);
        return nullptr;
    });
    object_class.add_reg_function("is", [](DabValue self, std::vector<DabValue> args) {
        assert(args.size() == 1);
        auto arg0 = self;
        auto arg1 = args[0];
        return arg0.is_a(arg1.get_class());
    });
    object_class.add_static_reg_function("to_s", [](DabValue self, std::vector<DabValue> args) {
        assert(args.size() == 0);
        return self.class_name();
    });
    object_class.add_static_reg_function("==", [](DabValue self, std::vector<DabValue> args) {
        assert(args.size() == 1);
        auto arg0 = self;
        auto arg1 = args[0];
        assert(arg0.data.type == TYPE_CLASS);
        assert(arg1.data.type == TYPE_CLASS);
        return DabValue(arg0.data.fixnum == arg1.data.fixnum);
    });

    auto &string_class = get_class(CLASS_STRING);
    string_class.add_reg_function("upcase", [](DabValue self, std::vector<DabValue> args) {
        assert(args.size() == 0);
        auto s = self.string();
        std::transform(s.begin(), s.end(), s.begin(), ::toupperc);
        return s;
    });
    string_class.add_reg_function("base64_decode", [](DabValue self, std::vector<DabValue> args) {
        assert(args.size() == 0);
        auto s = self.string();
        size_t outlen;
        auto decoded = (const char*)base64_decode(s.c_str(), s.length(), &outlen);
        return std::string(decoded, outlen);
    });
    string_class.add_reg_function("length", [](DabValue self, std::vector<DabValue> args) {
        assert(args.size() == 0);
        auto     s = self.string();
        DabValue ret(CLASS_INT32, (int)s.size());
        return ret;
    });
    string_class.add_reg_function("[]", [](DabValue self, std::vector<DabValue> args) {
        assert(args.size() == 1);
        auto arg = $VM->cast(args[0], CLASS_FIXNUM);
        auto s   = self.string();
        auto n   = arg.data.fixnum;
        return DabValue(s.substr((size_t)n, 1));
    });
    string_class.add_reg_function("+", [](DabValue self, std::vector<DabValue> args) {
        assert(args.size() == 1);
        auto arg0 = self;
        auto arg1 = $VM->cast(args[0], CLASS_STRING);
        auto s0   = arg0.string();
        auto s1   = arg1.string();
        return DabValue(s0 + s1);
    });
    string_class.add_static_reg_function("new", [](DabValue, std::vector<DabValue> args) {
        auto argc = args.size();
        assert(argc <= 2);
        std::string s;
        if (argc == 2)
        {
            auto        arg1   = $VM->cast(args[0], CLASS_BYTEBUFFER);
            auto        arg2   = $VM->cast(args[1], CLASS_FIXNUM);
            const auto &buffer = arg1.bytebuffer();
            const auto  length = arg2.data.fixnum;
            if (length)
            {
                s = std::string((const char *)&buffer[0], (size_t)length);
            }
        }
        else if (argc == 1)
        {
            s = args[0].string();
        }
        return DabValue::allocate_dynstr(s.c_str());
    });
    string_class.add_reg_function("to_s", [](DabValue self, std::vector<DabValue> args) {
        assert(args.size() == 0);
        if (!$VM->options.autorelease)
        {
            self.retain();
        }
        return self;
    });
    DAB_MEMBER_EQUALS_OPERATORS(string_class, CLASS_STRING, .string());
    DAB_MEMBER_COMPARE_OPERATORS(string_class, CLASS_STRING, .string());

    auto &fixnum_class = get_class(CLASS_FIXNUM);
    fixnum_class.add_static_reg_function("new", [](DabValue self, std::vector<DabValue> args) {
        assert(args.size() <= 1);
        auto     klass = self;
        DabValue ret_value;
        ret_value.data.type   = TYPE_FIXNUM;
        ret_value.data.fixnum = 0;
        if (args.size() == 1)
        {
            auto arg = args[0];
            assert(arg.data.type == TYPE_FIXNUM);
            ret_value.data.fixnum = arg.data.fixnum;
        }
        return ret_value;
    });
    DAB_MEMBER_NUMERIC_OPERATORS(fixnum_class, CLASS_FIXNUM, uint64_t, .data.fixnum);

    define_default_classes_int();

    auto &boolean_class = get_class(CLASS_BOOLEAN);
    DAB_MEMBER_EQUALS_OPERATORS(boolean_class, CLASS_BOOLEAN, .data.boolean);

    auto &array_class = get_class(CLASS_ARRAY);
    array_class.add_reg_function("count", [](DabValue self, std::vector<DabValue> args) {
        assert(args.size() == 0);
        assert(self.data.type == TYPE_ARRAY);
        return (uint64_t)self.array().size();
    });
    array_class.add_reg_function("shift", [](DabValue self, std::vector<DabValue> args) {
        assert(args.size() == 0);
        assert(self.data.type == TYPE_ARRAY);
        auto &a = self.array();
        if (a.size() == 0)
        {
            return DabValue(nullptr);
        }
        else
        {
            auto ret = a[0];
            a.erase(a.begin());
            return ret;
        }
    });
    array_class.add_reg_function("insert", [](DabValue self, std::vector<DabValue> args) {
        assert(args.size() == 1);
        auto arg = args[0];
        assert(self.data.type == TYPE_ARRAY);
        auto &a = self.array();
        a.push_back(arg);
        return nullptr;
    });
    array_class.add_reg_function("[]", [](DabValue self, std::vector<DabValue> args) {
        assert(args.size() == 1);
        auto arg0 = self;
        auto arg1 = args[0];
        assert(arg0.data.type == TYPE_ARRAY);
        assert(arg1.data.type == TYPE_FIXNUM);
        auto &a = arg0.array();
        auto  n = arg1.data.fixnum;
        if (n < 0)
            n = a.size() + n;
        if (n < 0 || n >= (int64_t)a.size())
            return DabValue(nullptr);
        else
            return a[(size_t)n];
    });
    array_class.add_reg_function("[]=", [](DabValue self, std::vector<DabValue> args) {
        assert(args.size() == 2);
        auto arg0 = self;
        auto arg1 = args[0];
        auto arg2 = args[1];
        assert(arg0.data.type == TYPE_ARRAY);
        assert(arg1.data.type == TYPE_FIXNUM);
        auto &a = arg0.array();
        auto  n = arg1.data.fixnum;
        if (n < 0)
            n = a.size() + n;
        if (n < 0 || n >= (int64_t)a.size())
        {
            throw DabRuntimeError("vm: index outside of array bounds.");
        }
        else
        {
            a[(size_t)n] = arg2;
        }
        return nullptr;
    });
    array_class.add_reg_function("join", [this](DabValue self, std::vector<DabValue> args) {
        assert(args.size() == 0);
        std::string ret;
        auto &      a = self.array();
        for (size_t i = 0; i < a.size(); i++)
        {
            if (i)
                ret += ", ";
            auto val = cinstcall(a[i], "to_s");
            ret += val.string();
            if (!$VM->options.autorelease)
            {
                val.release();
            }
        }
        return ret;
    });
    array_class.add_reg_function("to_s", [this](DabValue self, std::vector<DabValue> args) {
        assert(args.size() == 0);
        auto inner = cinstcall(self, "join");
        auto ret   = std::string("[" + inner.string() + "]");
        if (!$VM->options.autorelease)
        {
            inner.release();
        }
        return ret;
    });
    array_class.add_reg_function("+", [](DabValue self, std::vector<DabValue> args) {
        assert(args.size() == 1);
        auto arg = $VM->cast(args[0], CLASS_ARRAY);
        return $VM->merge_arrays(self, arg);
    });

    auto &method_class = get_class(CLASS_METHOD);
    method_class.add_reg_function("to_s", [](DabValue self, std::vector<DabValue> args) {
        assert(args.size() == 0);
        return std::string("@method(" + self.string() + ")");
    });
    method_class.add_reg_function("call", [](DabValue self, std::vector<DabValue> args) {
        return $VM->call_block(self, args);
    });

    auto &bytebuffer_class = get_class(CLASS_BYTEBUFFER);
    bytebuffer_class.add_static_reg_function("new", [](DabValue self, std::vector<DabValue> args) {
        assert(args.size() == 1);
        auto klass = self;
        assert(klass.data.type == TYPE_CLASS);

        auto instance = klass.create_instance();

        auto _size = $VM->cast(args[0], CLASS_FIXNUM);
        auto size  = _size.data.fixnum;
        instance.bytebuffer().resize((size_t)size);
        return instance;
    });
    bytebuffer_class.add_reg_function("[]", [](DabValue self, std::vector<DabValue> args) {
        assert(args.size() == 1);
        auto arg0 = self;
        auto arg1 = args[0];
        assert(arg0.data.type == TYPE_BYTEBUFFER);
        assert(arg1.data.type == TYPE_FIXNUM);
        auto &a = arg0.bytebuffer();
        auto  n = arg1.data.fixnum;
        if (n < 0)
            n = a.size() + n;
        if (n < 0 || n >= (int64_t)a.size())
            return DabValue(nullptr);
        else
            return DabValue(CLASS_UINT8, a[(size_t)n]);
    });
    bytebuffer_class.add_reg_function("[]=", [](DabValue self, std::vector<DabValue> args) {
        assert(args.size() == 2);
        auto arg0 = self;
        auto arg1 = args[0];
        auto arg2 = args[1];
        assert(arg0.data.type == TYPE_BYTEBUFFER);
        assert(arg1.data.type == TYPE_FIXNUM);
        auto &a = arg0.bytebuffer();
        auto  n = arg1.data.fixnum;
        if (n < 0)
            n = a.size() + n;
        if (n >= 0 && n < (int64_t)a.size())
        {
            a[(size_t)n] = $VM->cast(arg2, CLASS_UINT8).data.num_uint8;
        }
        return nullptr;
    });
    bytebuffer_class.add_reg_function("to_s", [](DabValue self, std::vector<DabValue> args) {
        assert(args.size() == 0);
        std::string ret;
        auto &      a = self.bytebuffer();
        for (size_t i = 0; i < a.size(); i++)
        {
            if (i)
                ret += ", ";
            char string[32];
            snprintf(string, sizeof(string), "%d", (int)a[i]);
            ret += string;
        }
        return "[" + ret + "]";
    });
}
