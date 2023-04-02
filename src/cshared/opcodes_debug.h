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
    {OP_LOAD_CLASS, "LOAD_CLASS", {OpcodeArg::ARG_REG, OpcodeArg::ARG_UINT16}},
    {OP_LOAD_METHOD, "LOAD_METHOD", {OpcodeArg::ARG_REG, OpcodeArg::ARG_SYMBOL}},
    {OP_REFLECT,
     "REFLECT",
     {OpcodeArg::ARG_REG, OpcodeArg::ARG_SYMBOL, OpcodeArg::ARG_UINT16, OpcodeArg::ARG_UINT16}},
    {OP_LOAD_NUMBER, "LOAD_NUMBER", {OpcodeArg::ARG_REG, OpcodeArg::ARG_UINT64}},
    {OP_LOAD_STRING,
     "LOAD_STRING",
     {OpcodeArg::ARG_REG, OpcodeArg::ARG_UINT64, OpcodeArg::ARG_UINT64}},
    {OP_NEW_ARRAY, "NEW_ARRAY", {OpcodeArg::ARG_REG, OpcodeArg::ARG_REGLIST}},
    {OP_LOAD_SELF, "LOAD_SELF", {OpcodeArg::ARG_REG}},
    {OP_GET_INSTVAR, "GET_INSTVAR", {OpcodeArg::ARG_REG, OpcodeArg::ARG_SYMBOL}},
    {OP_LOAD_HAS_BLOCK, "LOAD_HAS_BLOCK", {OpcodeArg::ARG_REG}},
    {OP_LOAD_ARG, "LOAD_ARG", {OpcodeArg::ARG_REG, OpcodeArg::ARG_UINT16}},
    {OP_JMP, "JMP", {OpcodeArg::ARG_INT16}},
    {OP_JMP_IF, "JMP_IF", {OpcodeArg::ARG_REG, OpcodeArg::ARG_INT16, OpcodeArg::ARG_INT16}},
    {OP_CALL, "CALL", {OpcodeArg::ARG_REG, OpcodeArg::ARG_SYMBOL, OpcodeArg::ARG_REGLIST}},
    {OP_INSTCALL,
     "INSTCALL",
     {OpcodeArg::ARG_REG, OpcodeArg::ARG_REG, OpcodeArg::ARG_SYMBOL, OpcodeArg::ARG_REGLIST}},
    {OP_SYSCALL, "SYSCALL", {OpcodeArg::ARG_REG, OpcodeArg::ARG_UINT8, OpcodeArg::ARG_REGLIST}},
    {OP_RETURN, "RETURN", {OpcodeArg::ARG_REG}},
    {OP_RETAIN, "RETAIN", {OpcodeArg::ARG_REG}},
    {OP_RELEASE, "RELEASE", {OpcodeArg::ARG_REG}},
    {OP_CAST, "CAST", {OpcodeArg::ARG_REG, OpcodeArg::ARG_REG, OpcodeArg::ARG_UINT16}},
    {OP_SET_INSTVAR, "SET_INSTVAR", {OpcodeArg::ARG_SYMBOL, OpcodeArg::ARG_REG}},
    {OP_COV, "COV", {OpcodeArg::ARG_UINT16, OpcodeArg::ARG_UINT16}},
    {OP_STACK_RESERVE, "STACK_RESERVE", {OpcodeArg::ARG_UINT16}},
    {OP_LOAD_FLOAT, "LOAD_FLOAT", {OpcodeArg::ARG_REG, OpcodeArg::ARG_FLOAT}},
    {OP_LOAD_ARG_DEFAULT,
     "LOAD_ARG_DEFAULT",
     {OpcodeArg::ARG_REG, OpcodeArg::ARG_UINT16, OpcodeArg::ARG_REG}},
    {OP_LOAD_LOCAL_BLOCK, "LOAD_LOCAL_BLOCK", {OpcodeArg::ARG_REG, OpcodeArg::ARG_REG}},
    {OP_LOAD_CURRENT_BLOCK, "LOAD_CURRENT_BLOCK", {OpcodeArg::ARG_REG}},
    {OP_BOX, "BOX", {OpcodeArg::ARG_REG, OpcodeArg::ARG_REG}},
    {OP_UNBOX, "UNBOX", {OpcodeArg::ARG_REG, OpcodeArg::ARG_REG}},
    {OP_SETBOX, "SETBOX", {OpcodeArg::ARG_REG, OpcodeArg::ARG_REG, OpcodeArg::ARG_REG}},
    {OP_GET_INSTVAR_EXT,
     "GET_INSTVAR_EXT",
     {OpcodeArg::ARG_REG, OpcodeArg::ARG_SYMBOL, OpcodeArg::ARG_REG}},
};
