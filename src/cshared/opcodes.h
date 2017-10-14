// Autogenerated from /src/shared/opcodes.rb

enum
{
    OP_NOP                  = 0x00,
    OP_PUSH_CLASS           = 0x01,
    OP_PUSH_CONSTANT        = 0x02,
    OP_PUSH_ARG             = 0x03,
    OP_PUSH_INSTVAR         = 0x04,
    OP_PUSH_SYMBOL          = 0x05,
    OP_PUSH_METHOD          = 0x06,
    OP_PUSH_SSA             = 0x07,
    OP_POP                  = 0x08,
    OP_CONSTANT_SYMBOL      = 0x09,
    OP_CONSTANT_STRING      = 0x0A,
    OP_CONSTANT_NUMBER      = 0x0B,
    OP_CAST                 = 0x0C,
    OP_JMP                  = 0x0D,
    OP_JMP_IF               = 0x0E,
    OP_JMP_IFN              = 0x0F,
    OP_JMP_IF2              = 0x10,
    OP_Q_JMP_IF2            = 0x11,
    OP_YIELD                = 0x12,
    OP_COV_FILE             = 0x13,
    OP_COV                  = 0x14,
    OP_START_FUNCTION       = 0x15,
    OP_LOAD_FUNCTION        = 0x16,
    OP_STACK_RESERVE        = 0x17,
    OP_DEFINE_CLASS         = 0x18,
    OP_BREAK_LOAD           = 0x19,
    OP_REFLECT              = 0x1A,
    OP_DESCRIBE_FUNCTION    = 0x1B,
    OP_Q_SET_CONSTANT       = 0x1C,
    OP_Q_SET_POP            = 0x1D,
    OP_Q_SET_NUMBER         = 0x1E,
    OP_Q_SET_ARG            = 0x1F,
    OP_Q_SET_CLASS          = 0x20,
    OP_Q_SET_CALL           = 0x21,
    OP_Q_SET_SYSCALL        = 0x22,
    OP_Q_SET_REG            = 0x23,
    OP_Q_SET_CLOSURE        = 0x24,
    OP_Q_SET_NIL            = 0x25,
    OP_Q_SET_INSTCALL       = 0x26,
    OP_Q_SET_CALL_BLOCK     = 0x27,
    OP_Q_SET_TRUE           = 0x28,
    OP_Q_SET_FALSE          = 0x29,
    OP_Q_SET_INSTVAR        = 0x2A,
    OP_Q_SET_INSTCALL_BLOCK = 0x2B,
    OP_Q_RELEASE            = 0x2C,
    OP_Q_CHANGE_INSTVAR     = 0x2D,
    OP_Q_RETURN             = 0x2E,
    OP_Q_RETAIN             = 0x2F,
    OP_Q_CAST               = 0x30,
    OP_Q_SET_NUMBER_INT32   = 0x31,
    OP_Q_SET_NUMBER_UINT8   = 0x32,
    OP_Q_SET_NUMBER_UINT32  = 0x33,
    OP_Q_SET_NUMBER_UINT64  = 0x34,
    OP_Q_SET_HAS_BLOCK      = 0x35,
    OP_Q_SET_NEW_ARRAY      = 0x36,
    OP_Q_SET_SELF           = 0x37,
    OP_Q_YIELD              = 0x38,
    OP_W_HEADER             = 0x39,
    OP_W_SECTION            = 0x3A,
    OP_W_END_HEADER         = 0x3B,
    OP_W_STRING             = 0x3C,
};
