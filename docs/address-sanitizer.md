---
layout: page
title: AddressSanitizer validation
---

Run the dedicated AddressSanitizer validation from the repository root:

```shell
bundle exec rake address_sanitizer_spec
```

This profile is initially supported only on Linux x86_64 with Clang 18. CI
runs it once in the blocking `address-sanitizer` job on GitHub-hosted
`ubuntu-24.04`; it is intentionally separate from the three-run Linux Ruby
matrix and the normal macOS and Windows jobs. No macOS or Windows sanitizer
support is claimed.

The command validates the test-suite and supported-toolchain manifests, checks
the profile-specific host and tools, and then generates only
`build/address-sanitizer/`. Its objects remain below
`build/address-sanitizer/obj/ASan/`, and its four target outputs remain below
`bin/address-sanitizer/`. The normal `build/`, `build/obj/Debug`,
`build/obj/Release`, and `bin/` outputs are not generated, cleaned, overwritten,
or substituted by this profile.

All `cvm`, `cdisasm`, `cdumpcov`, and `cffitest` sources retain fatal warnings
and are compiled with AddressSanitizer, use-after-scope instrumentation, debug
symbols, and frame-preserving options. The executable and shared-library link
steps also use AddressSanitizer. After the build, the gate checks every ELF
target for the AddressSanitizer initialization symbol; flag text alone is not
accepted as instrumentation proof.

A separate controlled heap-buffer-overflow canary is compiled under the same
profile and must produce the expected AddressSanitizer report and nonzero exit.
The canary lives only under `test/address_sanitizer/` and is not product or
fixture code. The gate then runs exact `--version` contracts for the three
executables and performs the reproducible legacy source-to-bytecode-to-native-VM
smoke twice through `bin/address-sanitizer/cvm`, with bounded stage timeouts.
Build failures, missing tools, timeouts, signals, sanitizer reports, metadata
mismatches, and output-contract mismatches are attributed and return nonzero.

Leak detection is enabled for the canary and for an explicit characterization
run of the trusted-local legacy VM smoke. That smoke currently has a
machine-checked baseline of 160 leaked bytes in four allocations. The gate must
observe exactly that leak-only fingerprint and no core address error; it then
runs the same external smoke with only leak detection disabled so the clean
source-to-VM contract can exercise all core AddressSanitizer checks. This narrow
second-run choice records leak remediation as later memory-ownership work rather
than hiding it with a global setting or suppression file.

The profile does not disable bounds, use-after-free, use-after-scope, stack, or
global detection. Runtime reports keep raw frame addresses because symbolizer
processes can hang independently of sanitizer detection; the binaries retain
debug symbols and frame pointers for offline attribution. The gate remains a
trusted-local execution check; it does not make hostile source or bytecode safe.

The audit's known `CLASS_STRING` to `CLASS_INTPTR` temporary `c_str()` lifetime
path in `src/cvm/main.cpp` belongs to the later dangling-pointer remediation
item. This profile neither fixes nor suppresses that path, and its bounded
legacy smoke does not claim to exercise FFI or every runtime ownership path.
Any sanitizer finding in the executed scope remains a gate failure.

Successful runs leave the isolated AddressSanitizer build and binary trees for
inspection. A later run removes only those two task-owned trees before
regenerating them.
