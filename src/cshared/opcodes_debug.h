// Autogenerated from /src/shared/opcodes.rb

const DabOpcodeInfo g_opcodes[] = {
    {OP_NOP, "NOP", {}},
    {OP_PUSH_NIL, "PUSH_NIL", {}},
    {OP_PUSH_SELF, "PUSH_SELF", {}},
    {OP_PUSH_TRUE, "PUSH_TRUE", {}},
    {OP_PUSH_FALSE, "PUSH_FALSE", {}},
    {OP_PUSH_STRING, "PUSH_STRING", {OpcodeArg::ARG_VLC}},
    {OP_PUSH_NUMBER, "PUSH_NUMBER", {OpcodeArg::ARG_UINT64}},
    {OP_PUSH_NUMBER_UINT8, "PUSH_NUMBER_UINT8", {OpcodeArg::ARG_UINT8}},
    {OP_PUSH_NUMBER_INT32, "PUSH_NUMBER_INT32", {OpcodeArg::ARG_INT32}},
    {OP_PUSH_NUMBER_UINT32, "PUSH_NUMBER_UINT32", {OpcodeArg::ARG_UINT32}},
    {OP_PUSH_NUMBER_UINT64, "PUSH_NUMBER_UINT64", {OpcodeArg::ARG_UINT64}},
    {OP_PUSH_ARRAY, "PUSH_ARRAY", {OpcodeArg::ARG_UINT16}},
    {OP_PUSH_CLASS, "PUSH_CLASS", {OpcodeArg::ARG_UINT16}},
    {OP_PUSH_CONSTANT, "PUSH_CONSTANT", {OpcodeArg::ARG_UINT16}},
    {OP_PUSH_ARG, "PUSH_ARG", {OpcodeArg::ARG_UINT16}},
    {OP_PUSH_INSTVAR, "PUSH_INSTVAR", {}},
    {OP_PUSH_SYMBOL, "PUSH_SYMBOL", {OpcodeArg::ARG_VLC}},
    {OP_PUSH_HAS_BLOCK, "PUSH_HAS_BLOCK", {}},
    {OP_PUSH_METHOD, "PUSH_METHOD", {OpcodeArg::ARG_VLC}},
    {OP_PUSH_SSA, "PUSH_SSA", {OpcodeArg::ARG_REG}},
    {OP_POP, "POP", {OpcodeArg::ARG_UINT16}},
    {OP_CONSTANT_SYMBOL, "CONSTANT_SYMBOL", {OpcodeArg::ARG_VLC}},
    {OP_CONSTANT_STRING, "CONSTANT_STRING", {OpcodeArg::ARG_VLC}},
    {OP_CONSTANT_NUMBER, "CONSTANT_NUMBER", {OpcodeArg::ARG_UINT64}},
    {OP_CAST, "CAST", {OpcodeArg::ARG_UINT16}},
    {OP_JMP, "JMP", {OpcodeArg::ARG_INT16}},
    {OP_JMP_IF, "JMP_IF", {OpcodeArg::ARG_INT16}},
    {OP_JMP_IFN, "JMP_IFN", {OpcodeArg::ARG_INT16}},
    {OP_JMP_IF2, "JMP_IF2", {OpcodeArg::ARG_INT16, OpcodeArg::ARG_INT16}},
    {OP_Q_JMP_IF2, "Q_JMP_IF2", {OpcodeArg::ARG_REG, OpcodeArg::ARG_INT16, OpcodeArg::ARG_INT16}},
    {OP_YIELD, "YIELD", {OpcodeArg::ARG_UINT16}},
    {OP_COV_FILE, "COV_FILE", {OpcodeArg::ARG_UINT16, OpcodeArg::ARG_VLC}},
    {OP_COV, "COV", {OpcodeArg::ARG_UINT16, OpcodeArg::ARG_UINT16}},
    {OP_START_FUNCTION,
     "START_FUNCTION",
     {OpcodeArg::ARG_VLC, OpcodeArg::ARG_UINT16, OpcodeArg::ARG_UINT16, OpcodeArg::ARG_UINT16}},
    {OP_LOAD_FUNCTION,
     "LOAD_FUNCTION",
     {OpcodeArg::ARG_UINT16, OpcodeArg::ARG_VLC, OpcodeArg::ARG_UINT16}},
    {OP_STACK_RESERVE, "STACK_RESERVE", {OpcodeArg::ARG_UINT16}},
    {OP_DEFINE_CLASS,
     "DEFINE_CLASS",
     {OpcodeArg::ARG_VLC, OpcodeArg::ARG_UINT16, OpcodeArg::ARG_UINT16}},
    {OP_BREAK_LOAD, "BREAK_LOAD", {}},
    {OP_REFLECT, "REFLECT", {OpcodeArg::ARG_UINT16}},
    {OP_DESCRIBE_FUNCTION, "DESCRIBE_FUNCTION", {OpcodeArg::ARG_VLC, OpcodeArg::ARG_UINT16}},
    {OP_Q_SET_CONSTANT, "Q_SET_CONSTANT", {OpcodeArg::ARG_REG, OpcodeArg::ARG_INT16}},
    {OP_Q_SET_POP, "Q_SET_POP", {OpcodeArg::ARG_REG}},
    {OP_Q_SET_NUMBER, "Q_SET_NUMBER", {OpcodeArg::ARG_REG, OpcodeArg::ARG_UINT64}},
    {OP_Q_SET_ARG, "Q_SET_ARG", {OpcodeArg::ARG_REG, OpcodeArg::ARG_UINT16}},
    {OP_Q_SET_CLASS, "Q_SET_CLASS", {OpcodeArg::ARG_REG, OpcodeArg::ARG_UINT16}},
    {OP_Q_SET_CALL,
     "Q_SET_CALL",
     {OpcodeArg::ARG_REG, OpcodeArg::ARG_SYMBOL, OpcodeArg::ARG_REGLIST}},
    {OP_Q_SET_SYSCALL,
     "Q_SET_SYSCALL",
     {OpcodeArg::ARG_REG, OpcodeArg::ARG_UINT8, OpcodeArg::ARG_REGLIST}},
    {OP_Q_SET_REG, "Q_SET_REG", {OpcodeArg::ARG_REG, OpcodeArg::ARG_REG}},
    {OP_Q_SET_CLOSURE, "Q_SET_CLOSURE", {OpcodeArg::ARG_REG, OpcodeArg::ARG_UINT16}},
    {OP_Q_SET_NIL, "Q_SET_NIL", {OpcodeArg::ARG_REG}},
    {OP_Q_SET_INSTCALL,
     "Q_SET_INSTCALL",
     {OpcodeArg::ARG_REG, OpcodeArg::ARG_REG, OpcodeArg::ARG_SYMBOL, OpcodeArg::ARG_REGLIST}},
    {OP_Q_SET_CALL_BLOCK,
     "Q_SET_CALL_BLOCK",
     {OpcodeArg::ARG_REG, OpcodeArg::ARG_SYMBOL, OpcodeArg::ARG_SYMBOL, OpcodeArg::ARG_REG,
      OpcodeArg::ARG_REGLIST}},
    {OP_Q_SET_TRUE, "Q_SET_TRUE", {OpcodeArg::ARG_REG}},
    {OP_Q_SET_FALSE, "Q_SET_FALSE", {OpcodeArg::ARG_REG}},
    {OP_Q_SET_INSTVAR, "Q_SET_INSTVAR", {OpcodeArg::ARG_REG, OpcodeArg::ARG_SYMBOL}},
    {OP_Q_SET_INSTCALL_BLOCK,
     "Q_SET_INSTCALL_BLOCK",
     {OpcodeArg::ARG_REG, OpcodeArg::ARG_REG, OpcodeArg::ARG_SYMBOL, OpcodeArg::ARG_SYMBOL,
      OpcodeArg::ARG_REG, OpcodeArg::ARG_REGLIST}},
    {OP_Q_RELEASE, "Q_RELEASE", {OpcodeArg::ARG_REG}},
    {OP_Q_CHANGE_INSTVAR, "Q_CHANGE_INSTVAR", {OpcodeArg::ARG_SYMBOL, OpcodeArg::ARG_REG}},
    {OP_Q_RETURN, "Q_RETURN", {OpcodeArg::ARG_REG}},
};
