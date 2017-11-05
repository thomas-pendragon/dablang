// Autogenerated from /src/shared/opcodes.rb

enum
{
    OP_NOP                  = 0x00,
    OP_MOV                  = 0x01,
    OP_LOAD_NIL             = 0x02,
    OP_LOAD_TRUE            = 0x03,
    OP_LOAD_FALSE           = 0x04,
    OP_LOAD_UINT8           = 0x05,
    OP_LOAD_UINT16          = 0x06,
    OP_LOAD_UINT32          = 0x07,
    OP_LOAD_UINT64          = 0x08,
    OP_LOAD_INT8            = 0x09,
    OP_LOAD_INT16           = 0x0A,
    OP_LOAD_INT32           = 0x0B,
    OP_LOAD_INT64           = 0x0C,
    OP_LOAD_CLASS           = 0x0D,
    OP_LOAD_METHOD          = 0x0E,
    OP_REFLECT              = 0x0F,
    OP_Q_SET_NUMBER         = 0x10,
    OP_Q_SET_STRING         = 0x11,
    OP_Q_SET_NEW_ARRAY      = 0x12,
    OP_Q_SET_SELF           = 0x13,
    OP_Q_SET_INSTVAR        = 0x14,
    OP_Q_SET_CLOSURE        = 0x15,
    OP_Q_SET_HAS_BLOCK      = 0x16,
    OP_Q_SET_ARG            = 0x17,
    OP_JMP                  = 0x18,
    OP_Q_JMP_IF2            = 0x19,
    OP_Q_SET_CALL           = 0x1A,
    OP_Q_SET_CALL_BLOCK     = 0x1B,
    OP_Q_SET_INSTCALL       = 0x1C,
    OP_Q_SET_INSTCALL_BLOCK = 0x1D,
    OP_Q_SET_SYSCALL        = 0x1E,
    OP_Q_YIELD              = 0x1F,
    OP_Q_RETURN             = 0x20,
    OP_Q_RETAIN             = 0x21,
    OP_Q_RELEASE            = 0x22,
    OP_Q_CAST               = 0x23,
    OP_Q_CHANGE_INSTVAR     = 0x24,
    OP_COV                  = 0x25,
    OP_STACK_RESERVE        = 0x26,
};
