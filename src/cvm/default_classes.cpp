#include "cvm.h"

void BaseDabVM::define_default_classes()
{
    DabClass object_class;
    object_class.index   = CLASS_OBJECT;
    object_class.name    = "Object";
    object_class.builtin = true;
    {
        DabFunction fun;
        fun.name    = "new";
        fun.regular = false;
        fun.extra   = [this](size_t n_args, size_t n_ret) {
            assert(n_args == 1);
            assert(n_ret == 1);
            auto arg = stack.pop_value();
            assert(arg.type == TYPE_CLASS);
            stack.push_value(arg.create_instance());
        };
        object_class.static_functions["new"] = fun;
    }
    {
        DabFunction fun;
        fun.name    = "class";
        fun.regular = false;
        fun.extra   = [this](size_t n_args, size_t n_ret) {
            assert(n_args == 1);
            assert(n_ret == 1);
            auto arg = stack.pop_value();
            stack.push_value(arg.get_class(*this));
        };
        object_class.functions["class"] = fun;
    }
    classes[CLASS_OBJECT] = object_class;

    {
        DabClass klass;
        klass.index   = CLASS_STRING;
        klass.name    = "String";
        klass.builtin = true;
        {
            DabFunction fun;
            fun.name    = "upcase";
            fun.regular = false;
            fun.extra   = [this](size_t n_args, size_t n_ret) {
                assert(n_args == 1);
                assert(n_ret == 1);
                auto arg0 = stack.pop_value();
                assert(arg0.type == TYPE_STRING);
                auto &s = arg0.string;
                std::transform(s.begin(), s.end(), s.begin(), ::toupper);
                stack.push(arg0);
            };
            klass.functions["upcase"] = fun;
        }
        {
            DabFunction fun;
            fun.name    = "new";
            fun.regular = false;
            fun.extra   = [this](size_t n_args, size_t n_ret) {
                assert(n_args == 1 || n_args == 2);
                assert(n_ret == 1);
                auto     klass = stack.pop_value();
                DabValue ret_value;
                ret_value.type = TYPE_STRING;
                ret_value.kind = VAL_STACK;
                if (n_args == 2)
                {
                    auto arg = stack.pop_value();
                    assert(arg.type == TYPE_STRING);
                    ret_value.string = arg.string;
                }
                stack.push_value(ret_value);
            };
            klass.static_functions["new"] = fun;
        }
        classes[CLASS_STRING] = klass;
    }

    DabClass literal_string_class;
    literal_string_class.index            = CLASS_LITERALSTRING;
    literal_string_class.name             = "LiteralString";
    literal_string_class.builtin          = true;
    literal_string_class.superclass_index = CLASS_STRING;
    classes[CLASS_LITERALSTRING]          = literal_string_class;

    {
        DabClass klass;
        klass.index   = CLASS_FIXNUM;
        klass.name    = "Fixnum";
        klass.builtin = true;
        {
            DabFunction fun;
            fun.name    = "new";
            fun.regular = false;
            fun.extra   = [this](size_t n_args, size_t n_ret) {
                assert(n_args == 1 || n_args == 2);
                assert(n_ret == 1);
                auto     klass = stack.pop_value();
                DabValue ret_value;
                ret_value.type   = TYPE_FIXNUM;
                ret_value.kind   = VAL_STACK;
                ret_value.fixnum = 0;
                if (n_args == 2)
                {
                    auto arg = stack.pop_value();
                    assert(arg.type == TYPE_FIXNUM);
                    ret_value.fixnum = arg.fixnum;
                }
                stack.push_value(ret_value);
            };
            klass.static_functions["new"] = fun;
        }
        classes[CLASS_FIXNUM] = klass;
    }

    DabClass literal_fixnum_class;
    literal_fixnum_class.index            = CLASS_LITERALFIXNUM;
    literal_fixnum_class.name             = "LiteralFixnum";
    literal_fixnum_class.builtin          = true;
    literal_fixnum_class.superclass_index = CLASS_FIXNUM;
    classes[CLASS_LITERALFIXNUM]          = literal_fixnum_class;

    DabClass boolean_class;
    boolean_class.index    = CLASS_BOOLEAN;
    boolean_class.name     = "Boolean";
    boolean_class.builtin  = true;
    classes[CLASS_BOOLEAN] = boolean_class;

    {
        DabClass klass;
        klass.index                   = CLASS_LITERALBOOLEAN;
        klass.name                    = "LiteralBoolean";
        klass.builtin                 = true;
        klass.superclass_index        = CLASS_BOOLEAN;
        classes[CLASS_LITERALBOOLEAN] = klass;
    }
}
