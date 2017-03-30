#include "cvm.h"

DabClass &DabVM::define_builtin_class(const std::string &name, size_t class_index,
                                      size_t superclass_index)
{
    DabClass klass;
    klass.index            = class_index;
    klass.name             = name;
    klass.builtin          = true;
    klass.superclass_index = superclass_index;
    classes[class_index]   = klass;
    return classes[class_index];
}

void DabVM::define_default_classes()
{
    auto &vm = *this;

    auto &object_class = define_builtin_class("Object", CLASS_OBJECT);
    object_class.add_static_function("new", [this](size_t n_args, size_t n_ret) {
        assert(n_args == 1);
        assert(n_ret == 1);
        auto arg = stack.pop_value();
        assert(arg.data.type == TYPE_CLASS);
        stack.push_value(arg.create_instance());
    });
    object_class.add_simple_function(vm, "class",
                                     [this](DabValue self) { return self.get_class(*this); });
    object_class.add_static_function("to_s", [this](size_t n_args, size_t n_ret) {
        assert(n_args == 1);
        assert(n_ret == 1);
        auto arg = stack.pop_value();
        stack.push_value(arg.get_class(*this).name);
    });

    auto &string_class = define_builtin_class("String", CLASS_STRING);
    string_class.add_simple_function(vm, "upcase", [](DabValue self) {
        auto arg0 = self;
        assert(arg0.data.type == TYPE_STRING);
        auto &s = arg0.data.string;
        std::transform(s.begin(), s.end(), s.begin(), ::toupper);
        return arg0;
    });
    string_class.add_function("[]", [this](size_t n_args, size_t n_ret) {
        assert(n_args == 2);
        assert(n_ret == 1);
        auto arg0 = stack.pop_value();
        auto arg1 = stack.pop_value();
        assert(arg0.data.type == TYPE_STRING);
        assert(arg1.data.type == TYPE_FIXNUM);
        auto &s = arg0.data.string;
        auto  n = arg1.data.fixnum;
        stack.push(s.substr(n, 1));
    });
    string_class.add_static_function("new", [this](size_t n_args, size_t n_ret) {
        assert(n_args == 1 || n_args == 2);
        assert(n_ret == 1);
        auto     klass = stack.pop_value();
        DabValue ret_value;
        ret_value.data.type = TYPE_STRING;
        ret_value.data.kind = VAL_STACK;
        if (n_args == 2)
        {
            auto arg = stack.pop_value();
            assert(arg.data.type == TYPE_STRING);
            ret_value.data.string = arg.data.string;
        }
        stack.push_value(ret_value);
    });

    define_builtin_class("LiteralString", CLASS_LITERALSTRING, CLASS_STRING);

    auto &fixnum_class = define_builtin_class("Fixnum", CLASS_FIXNUM);
    fixnum_class.add_static_function("new", [this](size_t n_args, size_t n_ret) {
        assert(n_args == 1 || n_args == 2);
        assert(n_ret == 1);
        auto     klass = stack.pop_value();
        DabValue ret_value;
        ret_value.data.type   = TYPE_FIXNUM;
        ret_value.data.kind   = VAL_STACK;
        ret_value.data.fixnum = 0;
        if (n_args == 2)
        {
            auto arg = stack.pop_value();
            assert(arg.data.type == TYPE_FIXNUM);
            ret_value.data.fixnum = arg.data.fixnum;
        }
        stack.push_value(ret_value);
    });
    fixnum_class.add_simple_function(vm, "to_s", [](DabValue self) {
        char ret[32];
        sprintf(ret, "%zd", self.data.fixnum);
        return std::string(ret);
    });

    define_builtin_class("LiteralFixnum", CLASS_LITERALFIXNUM, CLASS_FIXNUM);

    auto &boolean_class = define_builtin_class("Boolean", CLASS_BOOLEAN);
    boolean_class.add_simple_function(vm, "to_s", [](DabValue self) {
        return std::string(self.data.boolean ? "true" : "false");
    });

    auto &nil_class = define_builtin_class("NilClass", CLASS_NILCLASS);
    nil_class.add_simple_function(vm, "to_s", [](DabValue self) { return std::string("nil"); });

    auto &array_class = define_builtin_class("Array", CLASS_ARRAY);
    array_class.add_simple_function(vm, "count", [this](DabValue self) {
        assert(self.data.type == TYPE_ARRAY);
        return self.array().size();
    });
    array_class.add_function("[]", [this](size_t n_args, size_t n_ret) {
        assert(n_args == 2);
        assert(n_ret == 1);
        auto arg0 = stack.pop_value();
        auto arg1 = stack.pop_value();
        assert(arg0.data.type == TYPE_ARRAY);
        assert(arg1.data.type == TYPE_FIXNUM);
        auto &a = arg0.array();
        auto  n = arg1.data.fixnum;
        if (n < 0)
            n = a.size() + n;
        if (n < 0 || n >= a.size())
            stack.push_value(nullptr);
        else
            stack.push_value(a[n]);
    });
    array_class.add_function("[]=", [this](size_t n_args, size_t n_ret) {
        assert(n_args == 3);
        assert(n_ret == 1);
        auto arg0 = stack.pop_value();
        auto arg2 = stack.pop_value();
        auto arg1 = stack.pop_value();
        assert(arg0.data.type == TYPE_ARRAY);
        assert(arg1.data.type == TYPE_FIXNUM);
        auto &a = arg0.array();
        auto  n = arg1.data.fixnum;
        if (n < 0)
            n = a.size() + n;
        if (n < 0 || n >= a.size())
        {
            fprintf(stderr, "VM: index outside of array bounds.\n");
            exit(1);
        }
        else
        {
            a[n] = arg2;
            stack.push_value(nullptr);
        }
    });
    array_class.add_function("last", [this](size_t n_args, size_t n_ret) {
        assert(n_args == 1);
        assert(n_ret == 1);
        auto arg0 = stack.pop_value();
        assert(arg0.data.type == TYPE_ARRAY);
        auto &a = arg0.array();
        if (!a.size())
            stack.push_value(nullptr);
        else
            stack.push_value(a[a.size() - 1]);
    });
    array_class.add_function("first", [this](size_t n_args, size_t n_ret) {
        assert(n_args == 1);
        assert(n_ret == 1);
        auto arg0 = stack.pop_value();
        assert(arg0.data.type == TYPE_ARRAY);
        auto &a = arg0.array();
        if (!a.size())
            stack.push_value(nullptr);
        else
            stack.push_value(a[0]);
    });
}
