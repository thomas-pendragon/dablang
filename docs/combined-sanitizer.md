---
layout: page
title: Combined sanitizer validation
---

Run both supported sanitizer gates from the repository root with:

```shell
bundle exec rake combined_sanitizer_spec
```

This command is supported only for trusted local artifacts on Linux x86_64
with Clang and Clang++ 18. It does not claim hostile-input safety, sandboxing,
memory safety, macOS or Windows sanitizer support, or coverage for another
compiler or platform. The explicitly enabled unsafe FFI smoke remains an unsafe
capability check, not a containment boundary.

The machine-readable contract is `config/combined_sanitizer_gate.json`. It fixes
the invocation order to AddressSanitizer followed by UndefinedBehaviorSanitizer,
binds each invocation to its existing repository-root command and supported
toolchain profile, and lists the exact native targets, canaries, negative
control, lifetime regression, native version smokes, unsafe FFI denial/opt-in
smoke, and legacy source-to-VM smoke covered by each gate. Contract validation
rejects missing or reordered entries, duplicate or omitted targets, missing
trusted sources, profile/output drift, manifest drift, and workflow drift before
either expensive child gate starts.

The orchestrator is fail-fast. It runs each independent gate at most once and
requires both a zero exit and that gate's explicit pass marker before advancing.
A nonzero exit, signal, missing command, child-level failure, combined timeout,
or zero exit without the completion marker stops the sequence. The combined
command preserves the failing status (`124` for its timeout and `127` for a
missing command), identifies the sanitizer that failed, and reports every
remaining sanitizer as `NOT RUN`; a partial run is never reported as complete.
Each child gate retains its existing stage diagnostics, internal timeouts,
cleanup ownership, instrumentation proof, canary requirements, and sanitizer
report detection.

CI deliberately keeps the existing `address-sanitizer` and
`undefined-behavior-sanitizer` jobs as two independent blocking jobs. Repository
contracts require each independent command exactly once and require the
combined command zero times in the workflow. This preserves independent failure
evidence and allows both CI jobs to finish without adding a third job that would
repeat both expensive builds. The combined entrypoint is the deterministic
operator command; CI machine-checks its topology while executing the two
underlying gates independently.

Successful runs leave each gate's isolated build and binary trees for
inspection. AddressSanitizer still owns only `build/address-sanitizer/` and
`bin/address-sanitizer/`; UndefinedBehaviorSanitizer still owns only
`build/undefined-behavior-sanitizer/` and
`bin/undefined-behavior-sanitizer/`. Neither child may clean or reclassify the
other child's evidence.
