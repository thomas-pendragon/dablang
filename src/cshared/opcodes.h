// Autogenerated from /src/shared/opcodes.rb

enum
{
    OP_START_FUNCTION  = 0x00,
    OP_CONSTANT_SYMBOL = 0x01,
    OP_CONSTANT_STRING = 0x02,
    OP_PUSH_CONSTANT   = 0x03,
    OP_CALL            = 0x04,
    OP_SET_VAR         = 0x05,
    OP_PUSH_VAR        = 0x06,
    OP_PUSH_ARG        = 0x07,
    OP_CONSTANT_NUMBER = 0x08,
    OP_RETURN          = 0x09,
    OP_JMP             = 0x0A,
    OP_JMP_IFN         = 0x0B,
    OP_NOP             = 0x0C,
    OP_PUSH_NIL        = 0x0D,
    OP_KERNELCALL      = 0x0E,
    OP_PUSH_STRING     = 0x0F,
    OP_PUSH_CLASS      = 0x10,
    OP_INSTCALL        = 0x11,
    OP_PUSH_SELF       = 0x12,
    OP_PUSH_INSTVAR    = 0x13,
    OP_SET_INSTVAR     = 0x14,
    OP_PUSH_ARRAY      = 0x15,
    OP_PUSH_TRUE       = 0x16,
    OP_PUSH_FALSE      = 0x17,
    OP_BREAK_LOAD      = 0x18,
    OP_LOAD_FUNCTION   = 0x19,
    OP_DEFINE_CLASS    = 0x1A,
    OP_STACK_RESERVE   = 0x1B,
    OP_COV_FILE        = 0x1C,
    OP_COV             = 0x1D,
    OP_DUP             = 0x1E,
    OP_JMP_IF          = 0x1F,
    OP_POP             = 0x20,
    OP_HARDCALL        = 0x21,
    OP_PUSH_NUMBER     = 0x22,
};
