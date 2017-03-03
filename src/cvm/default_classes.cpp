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
    auto &object_class = define_builtin_class("Object", CLASS_OBJECT);
    object_class.add_static_function("new", [this](size_t n_args, size_t n_ret) {
        assert(n_args == 1);
        assert(n_ret == 1);
        auto arg = stack.pop_value();
        assert(arg.data.type == TYPE_CLASS);
        stack.push_value(arg.create_instance());
    });
    object_class.add_function("class", [this](size_t n_args, size_t n_ret) {
        assert(n_args == 1);
        assert(n_ret == 1);
        auto arg = stack.pop_value();
        stack.push_value(arg.get_class(*this));
    });

    auto &string_class = define_builtin_class("String", CLASS_STRING);
    string_class.add_function("upcase", [this](size_t n_args, size_t n_ret) {
        assert(n_args == 1);
        assert(n_ret == 1);
        auto arg0 = stack.pop_value();
        assert(arg0.data.type == TYPE_STRING);
        auto &s = arg0.data.string;
        std::transform(s.begin(), s.end(), s.begin(), ::toupper);
        stack.push(arg0);
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

    define_builtin_class("LiteralFixnum", CLASS_LITERALFIXNUM, CLASS_FIXNUM);

    define_builtin_class("Boolean", CLASS_BOOLEAN);

    define_builtin_class("NilClass", CLASS_NILCLASS);

    define_builtin_class("Array", CLASS_ARRAY);
}
