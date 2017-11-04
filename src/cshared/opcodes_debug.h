// Autogenerated from /src/shared/opcodes.rb

const DabOpcodeInfo g_opcodes[] = {
    {OP_NOP, "NOP", {}},
    {OP_MOV, "MOV", {OpcodeArg::ARG_REG, OpcodeArg::ARG_REG}},
    {OP_LOAD_NIL, "LOAD_NIL", {OpcodeArg::ARG_REG}},
    {OP_LOAD_TRUE, "LOAD_TRUE", {OpcodeArg::ARG_REG}},
    {OP_LOAD_FALSE, "LOAD_FALSE", {OpcodeArg::ARG_REG}},
    {OP_LOAD_UINT8, "LOAD_UINT8", {OpcodeArg::ARG_REG, OpcodeArg::ARG_UINT8}},
    {OP_LOAD_UINT16, "LOAD_UINT16", {OpcodeArg::ARG_REG, OpcodeArg::ARG_UINT16}},
    {OP_LOAD_UINT32, "LOAD_UINT32", {OpcodeArg::ARG_REG, OpcodeArg::ARG_UINT32}},
    {OP_LOAD_UINT64, "LOAD_UINT64", {OpcodeArg::ARG_REG, OpcodeArg::ARG_UINT64}},
    {OP_LOAD_INT8, "LOAD_INT8", {OpcodeArg::ARG_REG, OpcodeArg::ARG_INT8}},
    {OP_LOAD_INT16, "LOAD_INT16", {OpcodeArg::ARG_REG, OpcodeArg::ARG_INT16}},
    {OP_LOAD_INT32, "LOAD_INT32", {OpcodeArg::ARG_REG, OpcodeArg::ARG_INT32}},
    {OP_LOAD_INT64, "LOAD_INT64", {OpcodeArg::ARG_REG, OpcodeArg::ARG_INT64}},
    {OP_Q_SET_CLASS, "Q_SET_CLASS", {OpcodeArg::ARG_REG, OpcodeArg::ARG_UINT16}},
    {OP_Q_SET_METHOD, "Q_SET_METHOD", {OpcodeArg::ARG_REG, OpcodeArg::ARG_SYMBOL}},
    {OP_Q_SET_REFLECT,
     "Q_SET_REFLECT",
     {OpcodeArg::ARG_REG, OpcodeArg::ARG_SYMBOL, OpcodeArg::ARG_UINT16}},
    {OP_Q_SET_REFLECT2,
     "Q_SET_REFLECT2",
     {OpcodeArg::ARG_REG, OpcodeArg::ARG_SYMBOL, OpcodeArg::ARG_UINT16, OpcodeArg::ARG_UINT16}},
    {OP_Q_SET_NUMBER, "Q_SET_NUMBER", {OpcodeArg::ARG_REG, OpcodeArg::ARG_UINT64}},
    {OP_Q_SET_STRING,
     "Q_SET_STRING",
     {OpcodeArg::ARG_REG, OpcodeArg::ARG_UINT64, OpcodeArg::ARG_UINT64}},
    {OP_Q_SET_NEW_ARRAY, "Q_SET_NEW_ARRAY", {OpcodeArg::ARG_REG, OpcodeArg::ARG_REGLIST}},
    {OP_Q_SET_SELF, "Q_SET_SELF", {OpcodeArg::ARG_REG}},
    {OP_Q_SET_INSTVAR, "Q_SET_INSTVAR", {OpcodeArg::ARG_REG, OpcodeArg::ARG_SYMBOL}},
    {OP_Q_SET_CLOSURE, "Q_SET_CLOSURE", {OpcodeArg::ARG_REG, OpcodeArg::ARG_UINT16}},
    {OP_Q_SET_HAS_BLOCK, "Q_SET_HAS_BLOCK", {OpcodeArg::ARG_REG}},
    {OP_Q_SET_ARG, "Q_SET_ARG", {OpcodeArg::ARG_REG, OpcodeArg::ARG_UINT16}},
    {OP_JMP, "JMP", {OpcodeArg::ARG_INT16}},
    {OP_Q_JMP_IF2, "Q_JMP_IF2", {OpcodeArg::ARG_REG, OpcodeArg::ARG_INT16, OpcodeArg::ARG_INT16}},
    {OP_Q_SET_CALL,
     "Q_SET_CALL",
     {OpcodeArg::ARG_REG, OpcodeArg::ARG_SYMBOL, OpcodeArg::ARG_REGLIST}},
    {OP_Q_SET_CALL_BLOCK,
     "Q_SET_CALL_BLOCK",
     {OpcodeArg::ARG_REG, OpcodeArg::ARG_SYMBOL, OpcodeArg::ARG_SYMBOL, OpcodeArg::ARG_REG,
      OpcodeArg::ARG_REGLIST}},
    {OP_Q_SET_INSTCALL,
     "Q_SET_INSTCALL",
     {OpcodeArg::ARG_REG, OpcodeArg::ARG_REG, OpcodeArg::ARG_SYMBOL, OpcodeArg::ARG_REGLIST}},
    {OP_Q_SET_INSTCALL_BLOCK,
     "Q_SET_INSTCALL_BLOCK",
     {OpcodeArg::ARG_REG, OpcodeArg::ARG_REG, OpcodeArg::ARG_SYMBOL, OpcodeArg::ARG_SYMBOL,
      OpcodeArg::ARG_REG, OpcodeArg::ARG_REGLIST}},
    {OP_Q_SET_SYSCALL,
     "Q_SET_SYSCALL",
     {OpcodeArg::ARG_REG, OpcodeArg::ARG_UINT8, OpcodeArg::ARG_REGLIST}},
    {OP_Q_YIELD, "Q_YIELD", {OpcodeArg::ARG_REG, OpcodeArg::ARG_REGLIST}},
    {OP_Q_RETURN, "Q_RETURN", {OpcodeArg::ARG_REG}},
    {OP_Q_RETAIN, "Q_RETAIN", {OpcodeArg::ARG_REG}},
    {OP_Q_RELEASE, "Q_RELEASE", {OpcodeArg::ARG_REG}},
    {OP_Q_CAST, "Q_CAST", {OpcodeArg::ARG_REG, OpcodeArg::ARG_REG, OpcodeArg::ARG_UINT16}},
    {OP_Q_CHANGE_INSTVAR, "Q_CHANGE_INSTVAR", {OpcodeArg::ARG_SYMBOL, OpcodeArg::ARG_REG}},
    {OP_COV, "COV", {OpcodeArg::ARG_UINT16, OpcodeArg::ARG_UINT16}},
    {OP_STACK_RESERVE, "STACK_RESERVE", {OpcodeArg::ARG_UINT16}},
};
