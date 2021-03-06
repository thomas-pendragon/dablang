// Autogenerated from /src/shared/opcodes.rb

enum
{
    OP_NOP              = 0x00,
    OP_MOV              = 0x01,
    OP_LOAD_NIL         = 0x02,
    OP_LOAD_TRUE        = 0x03,
    OP_LOAD_FALSE       = 0x04,
    OP_LOAD_UINT8       = 0x05,
    OP_LOAD_UINT16      = 0x06,
    OP_LOAD_UINT32      = 0x07,
    OP_LOAD_UINT64      = 0x08,
    OP_LOAD_INT8        = 0x09,
    OP_LOAD_INT16       = 0x0A,
    OP_LOAD_INT32       = 0x0B,
    OP_LOAD_INT64       = 0x0C,
    OP_LOAD_CLASS       = 0x0D,
    OP_LOAD_METHOD      = 0x0E,
    OP_REFLECT          = 0x0F,
    OP_LOAD_NUMBER      = 0x10,
    OP_LOAD_STRING      = 0x11,
    OP_NEW_ARRAY        = 0x12,
    OP_LOAD_SELF        = 0x13,
    OP_GET_INSTVAR      = 0x14,
    OP_LOAD_CLOSURE     = 0x15,
    OP_LOAD_HAS_BLOCK   = 0x16,
    OP_LOAD_ARG         = 0x17,
    OP_JMP              = 0x18,
    OP_JMP_IF           = 0x19,
    OP_CALL             = 0x1A,
    OP_CALL_BLOCK       = 0x1B,
    OP_INSTCALL         = 0x1C,
    OP_INSTCALL_BLOCK   = 0x1D,
    OP_SYSCALL          = 0x1E,
    OP_YIELD            = 0x1F,
    OP_RETURN           = 0x20,
    OP_RETAIN           = 0x21,
    OP_RELEASE          = 0x22,
    OP_CAST             = 0x23,
    OP_SET_INSTVAR      = 0x24,
    OP_COV              = 0x25,
    OP_STACK_RESERVE    = 0x26,
    OP_LOAD_FLOAT       = 0x27,
    OP_LOAD_ARG_DEFAULT = 0x28,
};
