// Autogenerated from /src/shared/opcodes.rb

const DabOpcodeInfo g_opcodes[] = {
    {OP_NOP, "NOP", {}},
    {OP_PUSH_NIL, "PUSH_NIL", {}},
    {OP_PUSH_SELF, "PUSH_SELF", {}},
    {OP_PUSH_TRUE, "PUSH_TRUE", {}},
    {OP_PUSH_FALSE, "PUSH_FALSE", {}},
    {OP_PUSH_STRING, "PUSH_STRING", {ARG_VLC}},
    {OP_PUSH_NUMBER, "PUSH_NUMBER", {ARG_UINT64}},
    {OP_PUSH_NUMBER_UINT8, "PUSH_NUMBER_UINT8", {ARG_UINT8}},
    {OP_PUSH_NUMBER_INT32, "PUSH_NUMBER_INT32", {ARG_INT32}},
    {OP_PUSH_NUMBER_UINT32, "PUSH_NUMBER_UINT32", {ARG_UINT32}},
    {OP_PUSH_NUMBER_UINT64, "PUSH_NUMBER_UINT64", {ARG_UINT64}},
    {OP_PUSH_ARRAY, "PUSH_ARRAY", {ARG_UINT16}},
    {OP_PUSH_CLASS, "PUSH_CLASS", {ARG_UINT16}},
    {OP_PUSH_CONSTANT, "PUSH_CONSTANT", {ARG_UINT16}},
    {OP_PUSH_ARG, "PUSH_ARG", {ARG_UINT16}},
    {OP_PUSH_INSTVAR, "PUSH_INSTVAR", {ARG_VLC}},
    {OP_PUSH_SYMBOL, "PUSH_SYMBOL", {ARG_VLC}},
    {OP_PUSH_HAS_BLOCK, "PUSH_HAS_BLOCK", {}},
    {OP_PUSH_METHOD, "PUSH_METHOD", {ARG_VLC}},
    {OP_PUSH_SSA, "PUSH_SSA", {ARG_REG}},
    {OP_POP, "POP", {ARG_UINT16}},
    {OP_DUP, "DUP", {}},
    {OP_CONSTANT_SYMBOL, "CONSTANT_SYMBOL", {ARG_VLC}},
    {OP_CONSTANT_STRING, "CONSTANT_STRING", {ARG_VLC}},
    {OP_CONSTANT_NUMBER, "CONSTANT_NUMBER", {ARG_UINT64}},
    {OP_CALL, "CALL", {ARG_UINT16}},
    {OP_CALL_BLOCK, "CALL_BLOCK", {ARG_UINT16}},
    {OP_INSTCALL, "INSTCALL", {ARG_UINT16}},
    {OP_INSTCALL_BLOCK, "INSTCALL_BLOCK", {ARG_UINT16}},
    {OP_HARDCALL, "HARDCALL", {ARG_UINT16}},
    {OP_HARDCALL_BLOCK, "HARDCALL_BLOCK", {ARG_UINT16}},
    {OP_SYSCALL, "SYSCALL", {ARG_UINT8}},
    {OP_CAST, "CAST", {ARG_UINT16}},
    {OP_JMP, "JMP", {ARG_INT16}},
    {OP_JMP_IF, "JMP_IF", {ARG_INT16}},
    {OP_JMP_IFN, "JMP_IFN", {ARG_INT16}},
    {OP_JMP_IF2, "JMP_IF2", {ARG_INT16, ARG_INT16}},
    {OP_Q_JMP_IF2, "Q_JMP_IF2", {ARG_REG, ARG_INT16, ARG_INT16}},
    {OP_RETURN, "RETURN", {}},
    {OP_YIELD, "YIELD", {ARG_UINT16}},
    {OP_SET_INSTVAR, "SET_INSTVAR", {ARG_VLC}},
    {OP_COV_FILE, "COV_FILE", {ARG_UINT16, ARG_VLC}},
    {OP_COV, "COV", {ARG_UINT16, ARG_UINT16}},
    {OP_START_FUNCTION, "START_FUNCTION", {ARG_VLC, ARG_UINT16, ARG_UINT16, ARG_UINT16}},
    {OP_LOAD_FUNCTION, "LOAD_FUNCTION", {ARG_UINT16, ARG_VLC, ARG_UINT16}},
    {OP_STACK_RESERVE, "STACK_RESERVE", {ARG_UINT16}},
    {OP_DEFINE_CLASS, "DEFINE_CLASS", {ARG_VLC, ARG_UINT16, ARG_UINT16}},
    {OP_BREAK_LOAD, "BREAK_LOAD", {}},
    {OP_REFLECT, "REFLECT", {ARG_UINT16}},
    {OP_DESCRIBE_FUNCTION, "DESCRIBE_FUNCTION", {ARG_VLC, ARG_UINT16}},
    {OP_Q_SET_CONSTANT, "Q_SET_CONSTANT", {ARG_REG, ARG_INT16}},
    {OP_Q_SET_POP, "Q_SET_POP", {ARG_REG}},
    {OP_Q_SET_NUMBER, "Q_SET_NUMBER", {ARG_REG, ARG_UINT64}},
    {OP_Q_SET_ARG, "Q_SET_ARG", {ARG_REG, ARG_UINT16}},
    {OP_Q_SET_CLASS, "Q_SET_CLASS", {ARG_REG, ARG_UINT16}},
    {OP_Q_SET_CALL, "Q_SET_CALL", {ARG_REG, ARG_SYMBOL, ARG_REGLIST}},
    {OP_Q_SET_SYSCALL, "Q_SET_SYSCALL", {ARG_REG, ARG_UINT8, ARG_REGLIST}},
    {OP_Q_SET_REG, "Q_SET_REG", {ARG_REG, ARG_REG}},
    {OP_Q_SET_CLOSURE, "Q_SET_CLOSURE", {ARG_REG, ARG_UINT16}},
    {OP_Q_SET_NIL, "Q_SET_NIL", {ARG_REG}},
    {OP_Q_VOID_CALL, "Q_VOID_CALL", {ARG_SYMBOL, ARG_REGLIST}},
    {OP_Q_VOID_CALL_BLOCK, "Q_VOID_CALL_BLOCK", {ARG_SYMBOL, ARG_SYMBOL, ARG_REG, ARG_REGLIST}},
    {OP_Q_VOID_SYSCALL, "Q_VOID_SYSCALL", {ARG_UINT8, ARG_REGLIST}},
    {OP_Q_RELEASE, "Q_RELEASE", {ARG_REG}},
};
