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
    object_class.add_static_function("new", [this](size_t n_args, size_t n_ret, void *blockaddr) {
        assert(blockaddr == 0);
        assert(n_args == 1);
        assert(n_ret == 1);
        auto arg = stack.pop_value();
        assert(arg.data.type == TYPE_CLASS);
        auto instance = arg.create_instance();

        auto stack_pos = stack.size() + 1;

        instcall(instance, "__construct", 0, 1);

        // temporary hack
        while (stack.size() != stack_pos)
        {
            execute_single(instructions);
        }

        stack.pop_value();
        stack.push_value(instance);
    });
    object_class.add_simple_function("class", [](DabValue self) { return self.get_class(); });
    object_class.add_simple_function("to_s", [](DabValue self) { return "#" + self.class_name(); });
    object_class.add_simple_function("__construct", [](DabValue) { return nullptr; });
    object_class.add_simple_function("__destruct", [](DabValue) { return nullptr; });
    object_class.add_static_function("to_s", [](size_t n_args, size_t n_ret, void *blockaddr) {
        assert(blockaddr == 0);
        assert(n_args == 1);
        assert(n_ret == 1);
        auto &stack = $VM->stack;
        auto  arg   = stack.pop_value();
        stack.push_value(arg.class_name());
    });

    auto &string_class = define_builtin_class("String", CLASS_STRING);
    string_class.add_simple_function("upcase", [](DabValue self) {
        auto arg0 = self;
        assert(arg0.data.type == TYPE_STRING);
        auto &s = arg0.data.string;
        std::transform(s.begin(), s.end(), s.begin(), ::toupper);
        return arg0;
    });
    string_class.add_function("[]", [](size_t n_args, size_t n_ret, void *blockaddr) {
        assert(blockaddr == 0);
        assert(n_args == 2);
        assert(n_ret == 1);
        auto &stack = $VM->stack;
        auto  arg0  = stack.pop_value();
        auto  arg1  = stack.pop_value();
        assert(arg0.data.type == TYPE_STRING);
        assert(arg1.data.type == TYPE_FIXNUM);
        auto &s = arg0.data.string;
        auto  n = arg1.data.fixnum;
        stack.push(s.substr(n, 1));
    });
    string_class.add_static_function("new", [](size_t n_args, size_t n_ret, void *blockaddr) {
        assert(blockaddr == 0);
        assert(n_args == 1 || n_args == 2);
        assert(n_ret == 1);
        auto &   stack = $VM->stack;
        auto     klass = stack.pop_value();
        DabValue ret_value;
        ret_value.data.type = TYPE_STRING;
        if (n_args == 2)
        {
            auto arg = stack.pop_value();
            assert(arg.data.type == TYPE_STRING);
            ret_value.data.string = arg.data.string;
        }
        stack.push_value(ret_value);
    });
    string_class.add_simple_function("to_s", [](DabValue self) { return self; });

    define_builtin_class("LiteralString", CLASS_LITERALSTRING, CLASS_STRING);

    auto &fixnum_class = define_builtin_class("Fixnum", CLASS_FIXNUM);
    fixnum_class.add_static_function("new", [](size_t n_args, size_t n_ret, void *blockaddr) {
        assert(blockaddr == 0);
        assert(n_args == 1 || n_args == 2);
        assert(n_ret == 1);
        auto &   stack = $VM->stack;
        auto     klass = stack.pop_value();
        DabValue ret_value;
        ret_value.data.type   = TYPE_FIXNUM;
        ret_value.data.fixnum = 0;
        if (n_args == 2)
        {
            auto arg = stack.pop_value();
            assert(arg.data.type == TYPE_FIXNUM);
            ret_value.data.fixnum = arg.data.fixnum;
        }
        stack.push_value(ret_value);
    });
    fixnum_class.add_simple_function("to_s", [](DabValue self) {
        char ret[32];
        sprintf(ret, "%" PRId64, self.data.fixnum);
        return std::string(ret);
    });

    define_builtin_class("LiteralFixnum", CLASS_LITERALFIXNUM, CLASS_FIXNUM);

    auto &uint8_class = define_builtin_class("Uint8", CLASS_UINT8, CLASS_FIXNUM);
    uint8_class.add_simple_function("to_s", [](DabValue self) {
        char ret[32];
        sprintf(ret, "%d", self.data.num_uint8);
        return std::string(ret);
    });

    auto &boolean_class = define_builtin_class("Boolean", CLASS_BOOLEAN);
    boolean_class.add_simple_function(
        "to_s", [](DabValue self) { return std::string(self.data.boolean ? "true" : "false"); });

    auto &nil_class = define_builtin_class("NilClass", CLASS_NILCLASS);
    nil_class.add_simple_function("to_s", [](DabValue) { return std::string("nil"); });

    auto &array_class = define_builtin_class("Array", CLASS_ARRAY);
    array_class.add_simple_function("count", [](DabValue self) {
        assert(self.data.type == TYPE_ARRAY);
        return (uint64_t)self.array().size();
    });
    array_class.add_function("insert", [this](size_t n_args, size_t n_ret, void *blockaddr) {
        assert(blockaddr == 0);
        assert(n_args == 2);
        assert(n_ret == 1);
        auto self = stack.pop_value();
        auto arg  = stack.pop_value();
        assert(self.data.type == TYPE_ARRAY);
        auto &a = self.array();
        a.push_back(arg);
        stack.push_value(nullptr);
    });
    array_class.add_function("[]", [this](size_t n_args, size_t n_ret, void *blockaddr) {
        assert(blockaddr == 0);
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
        if (n < 0 || n >= (int64_t)a.size())
            stack.push_value(nullptr);
        else
            stack.push_value(a[n]);
    });
    array_class.add_function("[]=", [this](size_t n_args, size_t n_ret, void *blockaddr) {
        assert(blockaddr == 0);
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
        if (n < 0 || n >= (int64_t)a.size())
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
    array_class.add_simple_function("join", [this](DabValue self) {
        std::string ret;
        auto &      a = self.array();
        for (size_t i = 0; i < a.size(); i++)
        {
            if (i)
                ret += ", ";
            instcall(a[i], "to_s", 0, 1);
            auto val = stack.pop_value();
            ret += val.data.string;
        }
        return ret;
    });
    array_class.add_function("each", [this](size_t n_args, size_t n_ret, void *blockaddr) {
        assert(n_args == 1);
        assert(n_ret == 1);
        auto  self = stack.pop_value();
        auto &a    = self.array();
        for (size_t i = 0; i < a.size(); i++)
        {
            this->yield(blockaddr, {a[i]});
        }
        stack.push_value(nullptr);
    });
    array_class.add_simple_function("to_s", [this](DabValue self) {
        instcall(self, "join", 0, 1);
        auto inner = stack.pop_value();
        return std::string("[" + inner.data.string + "]");
    });
}
