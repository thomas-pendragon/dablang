---
layout: page
title: Unsafe FFI capability
---

Dab's native FFI is an explicit unsafe capability for trusted local programs.
It is disabled by default. A program that reaches `__dlimport` without the
capability exits with status `1` and this diagnostic:

```text
vm: unsafe FFI is disabled; use --allow-unsafe-ffi only for trusted local code.
```

To preserve the prototype's existing native-call behavior for a trusted local
program, opt in when starting the VM:

```shell
bin/cvm --allow-unsafe-ffi program.dabcb
```

The flag applies only to that VM process. Source using the `import_libc` helper
and source calling raw `__dlimport` both reach the same gate in
`DabVM::kernel_dlimport`; an annotation, standard-library wrapper, or direct
syscall cannot grant the capability. Programs that do not reach `__dlimport`
are unaffected.

The opt-in allows the prior arbitrary native library and symbol loading path on
supported Unix hosts. It is not a sandbox, permission system, ABI validator, or
claim that native calls are memory-safe. It does not validate signatures,
manage pointers retained by foreign code, narrow the trusted-local input
boundary, or add native entry points. FFI remains unavailable on Windows: with
the opt-in present, the VM retains the existing `function import not supported
on windows yet` failure.

The ordinary complete gate runs the focused capability contract:

```shell
bundle exec rake unsafe_ffi_capability_spec
```

That contract compiles a program that calls raw `__dlimport`, proves the exact
denied diagnostic and status without the flag, and then proves successful
trusted-local behavior with the flag on Unix or the unchanged unsupported
boundary on Windows. The dedicated AddressSanitizer and
UndefinedBehaviorSanitizer jobs run the same denied and opted-in Unix contract
through their instrumented VMs. These checks cover only the exercised FFI call;
they do not establish general ABI, pointer-ownership, or hostile-input safety.
