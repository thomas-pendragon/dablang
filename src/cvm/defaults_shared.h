#pragma once

#define STR2(s) #s
#define STR(s) STR2(s)

#define DAB_MEMBER_OPERATOR(klass, cast_to, operator, result_class, result_type, member)           \
    klass.add_reg_function(STR(operator), [](DabValue self, std::vector<DabValue> args) {          \
        assert(args.size() == 1);                                                                  \
        auto arg0 = self;                                                                          \
        auto arg1 = $VM->cast(args[0], cast_to);                                                   \
        auto v0   = arg0 member;                                                                   \
        auto v1   = arg1 member;                                                                   \
                                                                                                   \
        DabValue ret(result_class, (result_type)(v0 operator v1));                                 \
        return ret;                                                                                \
    })

#define DAB_MEMBER_EQ_OPERATOR(klass, cast_to, operator, result_class, result_type, member)        \
    klass.add_function(STR(operator), [](size_t n_args, size_t n_ret, void *blockaddr) {           \
        assert(n_args == 2);                                                                       \
        assert(n_ret == 1);                                                                        \
        assert(blockaddr == 0);                                                                    \
        auto &   stack = $VM->stack;                                                               \
        auto     arg0  = stack.pop_value();                                                        \
        auto     arg1  = stack.pop_value();                                                        \
        DabValue ret;                                                                              \
        try                                                                                        \
        {                                                                                          \
            arg1    = $VM->cast(arg1, cast_to);                                                    \
            auto v0 = arg0 member;                                                                 \
            auto v1 = arg1 member;                                                                 \
            ret     = DabValue(result_class, (result_type)(v0 operator v1));                       \
        }                                                                                          \
        catch (DabCastError & error)                                                               \
        {                                                                                          \
            ret = DabValue(result_class, (bool)(true operator false));                             \
        }                                                                                          \
        stack.push(ret);                                                                           \
    })

#define DAB_MEMBER_EQUALS_OPERATORS(klass, cast_to, member)                                        \
    DAB_MEMBER_EQ_OPERATOR(klass, cast_to, ==, CLASS_BOOLEAN, bool, member);                       \
    DAB_MEMBER_EQ_OPERATOR(klass, cast_to, !=, CLASS_BOOLEAN, bool, member)

#define DAB_MEMBER_COMPARE_OPERATORS(klass, cast_to, member)                                       \
    DAB_MEMBER_OPERATOR(klass, cast_to, >, CLASS_BOOLEAN, bool, member);                           \
    DAB_MEMBER_OPERATOR(klass, cast_to, >=, CLASS_BOOLEAN, bool, member);                          \
    DAB_MEMBER_OPERATOR(klass, cast_to, <=, CLASS_BOOLEAN, bool, member);                          \
    DAB_MEMBER_OPERATOR(klass, cast_to, <, CLASS_BOOLEAN, bool, member)

#define DAB_MEMBER_NUMERIC_OPERATORS(klass, cast_to, result_type, member)                          \
    DAB_MEMBER_EQUALS_OPERATORS(klass, cast_to, member);                                           \
    DAB_MEMBER_COMPARE_OPERATORS(klass, cast_to, member);                                          \
    DAB_MEMBER_OPERATOR(klass, cast_to, +, cast_to, result_type, member);                          \
    DAB_MEMBER_OPERATOR(klass, cast_to, -, cast_to, result_type, member);                          \
    DAB_MEMBER_OPERATOR(klass, cast_to, *, cast_to, result_type, member);                          \
    DAB_MEMBER_OPERATOR(klass, cast_to, /, cast_to, result_type, member);                          \
    DAB_MEMBER_OPERATOR(klass, cast_to, %, cast_to, result_type, member);                          \
    DAB_MEMBER_OPERATOR(klass, cast_to, <<, cast_to, result_type, member);                         \
    DAB_MEMBER_OPERATOR(klass, cast_to, >>, cast_to, result_type, member);                         \
    DAB_MEMBER_OPERATOR(klass, cast_to, |, cast_to, result_type, member);                          \
    DAB_MEMBER_OPERATOR(klass, cast_to, &, cast_to, result_type, member)
