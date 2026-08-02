---
layout: page
title: UndefinedBehaviorSanitizer validation
---

Run the dedicated UndefinedBehaviorSanitizer validation from the repository
root:

```shell
bundle exec rake undefined_behavior_sanitizer_spec
```

This profile is supported only on Linux x86_64 with Clang and Clang++ 18. CI
runs it once in the blocking `undefined-behavior-sanitizer` job on
GitHub-hosted `ubuntu-24.04`. It is independent from the five normal CI runs
and the AddressSanitizer job. No macOS or Windows UndefinedBehaviorSanitizer
support is claimed.

The [combined sanitizer command](/combined-sanitizer.html) invokes this complete
gate after the AddressSanitizer gate. It does not replace this profile, alter its
evidence, or combine the two sanitizer instrumentations into one binary.

The command validates the test-suite and supported-toolchain manifests, checks
the profile-specific host, compilers, build driver, ELF metadata reader,
offline symbolizer, Premake version, and workflow contract, and then generates
only `build/undefined-behavior-sanitizer/`. Objects remain below
`build/undefined-behavior-sanitizer/obj/UBSan/`, and all four outputs remain
below `bin/undefined-behavior-sanitizer/`. The normal and AddressSanitizer build,
object, and binary trees are neither generated nor cleaned by this profile.

All `cvm`, `cdisasm`, `cdumpcov`, and `cffitest` sources retain fatal warnings.
They are compiled with `-fsanitize=undefined`,
`-fno-sanitize-recover=all`, debug symbols, retained frame pointers, and
disabled sibling-call optimization. Every executable and shared-library link
step uses `-fsanitize=undefined`. The gate checks each generated Makefile for
those flags and isolated paths, then requires a non-recovering
`__ubsan_handle_*_abort` ELF symbol in every final target. Flag text alone is
not accepted as instrumentation proof.

The non-product canary under `test/undefined_behavior_sanitizer/` uses volatile
operands to produce runtime signed integer overflow without constant folding.
The gate first compiles the same source normally and proves that the resulting
ELF binary fails the UBSan handler-symbol test. It then compiles the UBSan
canary, proves its instrumentation, and executes it with exactly:

```text
UBSAN_OPTIONS=exitcode=86:halt_on_error=1:print_stacktrace=1:symbolize=0
```

The canary must exit `86`, emit a signed-integer-overflow diagnostic, a UBSan
summary, and a stack frame, and produce no standard output. Live symbolizer
processes can hang independently of UBSan detection, so the bounded runtime
contract keeps raw stack addresses. Debug symbols and frame pointers remain in
every target, and the gate requires `/usr/bin/llvm-symbolizer-18` for offline
attribution. No core UBSan check is disabled, recovered, suppressed, or placed
on an ignore list.

The gate next checks exact `--version` output for all three executables, deriving
the expected release only from root `VERSION`. It finally performs the bounded,
reproducible legacy source-to-bytecode-to-native-VM smoke through
`bin/undefined-behavior-sanitizer/cvm`. Any UBSan diagnostic, crash, signal,
timeout, build or tool mismatch, malformed contract, instrumentation mismatch,
or unexpected output fails with the stage, command, status, and captured output
where applicable. Successful output stays limited to stage announcements and a
final pass line.

The gate owns only `build/undefined-behavior-sanitizer/` and
`bin/undefined-behavior-sanitizer/`. Each run removes those two trees after
validating the host, profile, and tools, then leaves the newly generated
artifacts available for inspection. Temporary legacy-smoke workspaces are
removed by their owning runner even on failure.

This remains a trusted-local execution check, not a sandbox or hostile-bytecode
claim. The gate compiles and runs the focused `CLASS_STRING` to `CLASS_INTPTR`
owner-copy and release regression with UBSan enabled. It also runs the
[unsafe FFI capability contract](/unsafe-ffi.html) through the instrumented VM,
proving default denial and one explicitly enabled libc call. That bounded call
does not claim general ABI or pointer-ownership coverage; any UBSan finding in
the executed scope remains a gate failure.
