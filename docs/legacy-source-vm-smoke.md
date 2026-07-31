---
layout: page
title: Legacy source-to-VM smoke
---

Run the reproducible legacy source smoke from the repository root:

```shell
bundle exec rake legacy_source_vm_smoke
```

The task builds the platform-native `bin/cvm` executable (`bin/cvm.exe` on
Windows), then runs the checked-in
[`test/legacy_source_vm_smoke/program.dab`](https://github.com/thomas-pendragon/dablang/blob/master/test/legacy_source_vm_smoke/program.dab)
through the shipped production tools. The program uses deterministic arithmetic
and output. It does not use FFI, input, the filesystem, the environment, the
clock, randomness, or the network.

## Characterized production path

The current external legacy pipeline is:

1. `ruby src/compiler/compiler.rb SOURCE` parses and compiles `.dab` source.
   Assembly text is the command's stdout and becomes a `.dabca` artifact.
   Diagnostics are stderr; a nonzero status stops the smoke.
2. `ruby src/tobinary/tobinary.rb` reads that assembly text on stdin. Portable
   DAB bytecode is stdout and becomes a `.dabcb` artifact. Diagnostics are
   stderr; a nonzero status stops the smoke.
3. `bin/cvm[.exe] BYTECODE` loads and executes the `.dabcb`. Program output is
   stdout, current prototype loader/runtime diagnostics are stderr, and the
   process status is the execution status.

The existing `dab_fixture_spec` proves a large source behavior corpus, but its
frontend extracts source from `.dabt` files and invokes compiler and assembler
entrypoints in-process. The `asm_spec` and `vm_spec` suites separately prove
assembler and VM behavior. Those suites remain authoritative for their existing
contracts, but none previously exercised the complete shipped external command
path from a checked-in `.dab` source through native execution.

## Reproducibility and failure contract

The smoke copies the canonical source into two independent task-owned temporary
directories whose names contain spaces. Each directory gets a fresh external
compiler, assembler, and VM run. Process arguments are passed without a shell;
the platform executable suffix is derived from Ruby's native configuration.

The smoke requires:

- nonempty `.dabcb` output that is byte-for-byte identical between both builds,
  without normalization;
- exact stdout and exit status from
  `test/legacy_source_vm_smoke/contract.json` for both executions; and
- byte-for-byte identical VM stderr between both executions.

The VM currently emits prototype loader and lifecycle diagnostics on stderr.
Their exact text is intentionally not a language promise, so the contract
requires reproducibility across the two runs rather than committing incidental
diagnostic text. Compiler and assembler informational diagnostics are captured
but likewise are not frozen on successful runs.

Compiler and assembler stages have 30-second limits; native VM execution has a
10-second limit. A command failure or timeout stops immediately and reports the
stage, argument-safe displayed command, exit status, and captured stdout and
stderr. Reproducibility or runtime-contract mismatches report the responsible
contract and return nonzero. Ruby's temporary-directory blocks remove only the
two directories created by the smoke, including on failure.

This is a trusted-local-source and generated-artifact check. It does not claim
safe execution of hostile source or bytecode and does not change the existing
FFI boundary.
