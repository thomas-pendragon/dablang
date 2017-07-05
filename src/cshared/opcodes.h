// Autogenerated from /src/shared/opcodes.rb

enum
{
    OP_NOP             = 0x00,
    OP_PUSH_NIL        = 0x01,
    OP_PUSH_SELF       = 0x02,
    OP_PUSH_TRUE       = 0x03,
    OP_PUSH_FALSE      = 0x04,
    OP_PUSH_STRING     = 0x05,
    OP_PUSH_NUMBER     = 0x06,
    OP_PUSH_ARRAY      = 0x07,
    OP_PUSH_CLASS      = 0x08,
    OP_PUSH_CONSTANT   = 0x09,
    OP_PUSH_ARG        = 0x0A,
    OP_PUSH_VAR        = 0x0B,
    OP_PUSH_INSTVAR    = 0x0C,
    OP_PUSH_SYMBOL     = 0x0D,
    OP_POP             = 0x0E,
    OP_DUP             = 0x0F,
    OP_CONSTANT_SYMBOL = 0x10,
    OP_CONSTANT_STRING = 0x11,
    OP_CONSTANT_NUMBER = 0x12,
    OP_CALL            = 0x13,
    OP_INSTCALL        = 0x14,
    OP_HARDCALL        = 0x15,
    OP_SYSCALL         = 0x16,
    OP_JMP             = 0x17,
    OP_JMP_IF          = 0x18,
    OP_JMP_IFN         = 0x19,
    OP_RETURN          = 0x1A,
    OP_SET_VAR         = 0x1B,
    OP_SET_INSTVAR     = 0x1C,
    OP_COV_FILE        = 0x1D,
    OP_COV             = 0x1E,
    OP_START_FUNCTION  = 0x1F,
    OP_LOAD_FUNCTION   = 0x20,
    OP_STACK_RESERVE   = 0x21,
    OP_DEFINE_CLASS    = 0x22,
    OP_BREAK_LOAD      = 0x23,
    OP_YIELD           = 0x24,
    OP_CALL_BLOCK      = 0x25,
    OP_INSTCALL_BLOCK  = 0x26,
    OP_RELEASE_VAR     = 0x27,
    OP_SETV_NEW_ARRAY  = 0x28,
    OP_SETV_CALL       = 0x29,
    OP_SETV_CONSTANT   = 0x2A,
    OP_PUSH_HAS_BLOCK  = 0x2B,
    OP_HARDCALL_BLOCK  = 0x2C,
    OP_CAST            = 0x2D,
};
