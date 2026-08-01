# Unknown opcode fixture contract

Scenario B roadmap item 17 accepts deterministic rejection of unknown opcodes
for Dab 0.0.21. The generated real-opcode table in
`src/shared/opcodes.rb` defines the supported instruction values.

Before this item, the native VM rejected an unknown opcode only in the
`execute_single` switch fallback. Verbose execution indexed opcode metadata
first, and the shared disassembler and coverage dumper asserted before indexing
the same metadata. Malformed code could therefore produce an out-of-bounds
read, an assertion abort, or a platform-dependent signal instead of one tool
error.

Every native instruction decoder now validates the byte against the generated
real-opcode table before reading opcode metadata or operand format data. An
invalid byte is reported to standard error in this exact shape:

```text
<consumer>: <stage>: unknown opcode <decimal> (0x<two lowercase hex digits>) at byte <offset>.
```

The decimal value is bounded to the byte range `0` through `255`, and the byte
offset is an unsigned 64-bit artifact position. The process exits with status
`2`. The consumers and stages covered by this contract are VM execution, VM
debugger disassembly, native disassembly, and coverage-dump decoding. Verbose
VM mode may retain trace output for earlier valid instructions, but its unknown
opcode line and exit status are identical to default mode.

This is behavior-preserving for every opcode generated from
`src/shared/opcodes.rb`. It is intentionally breaking only for malformed
artifacts that previously reached an assertion, signal, metadata over-read, or
the VM's late exit-status-`1` fallback. Such artifacts are rejected because an
unknown opcode has no supported meaning.

`control.dabca` assembles to supported version-3 bytecode and places the highest
generated opcode at a valid code boundary. Valid `NOP` instructions keep the
fixture's existing 16-bit operands naturally aligned so this opcode-specific
contract does not depend on the separate operand-alignment boundary. The
executable contract changes exactly one byte at that code position or at the
`main` entry point to the first unknown value or `255`. It exercises default
and verbose VM execution, VM debugger disassembly, native disassembly, and
coverage dumping, alongside unchanged valid execution and disassembly.

This contract validates only opcode identity. It does not validate truncated
instructions, operands, section payload ranges, strings, symbols, bytecode
semantics, FFI, or any other artifact boundary. Dab remains suitable only for
trusted local input; this item does not establish hostile-bytecode safety.
