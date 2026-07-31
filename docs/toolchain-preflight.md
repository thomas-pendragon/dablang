---
layout: page
title: Supported toolchain preflight
---

Run the fast, read-only supported-toolchain check from the repository root:

```shell
ruby script/toolchain_preflight.rb
```

The command accepts the currently tested x86_64 environments:

| Platform | Ruby | Bundler | Premake | Build driver | Native compiler | Formatter |
| --- | --- | --- | --- | --- | --- | --- |
| Linux x86_64 | 3.3.12, 3.4.9, or 4.0.5 | 2.7.2 | 5.0.0-beta8 | Premake `gmake` and `make` | `g++` | `clang-format` |
| macOS x86_64 | 3.3.12 | 2.7.2 | 5.0.0-beta8 | Premake `gmake` and `make` | `clang++` | Homebrew `llvm@18` `clang-format` in CI |
| Windows x86_64 | 3.3.12 | 2.7.2 | 5.0.0-beta8 | Premake `gmake` and `make` | `g++` | `clang-format` |

Premake can be selected with `PREMAKE`, and clang-format can be selected with
`CLANG_FORMAT`. The preflight reports the resolved paths and detected versions.
Compiler, `make`, and clang-format release numbers are reported but are not
pinned because the current CI contract only proves their availability on the
named runners.

The separate [AddressSanitizer profile](/address-sanitizer.html) narrows its
supported environment further to Linux x86_64, GitHub-hosted `ubuntu-24.04`,
and Clang 18. Its gate performs the additional exact compiler, build-layout,
instrumentation, and runtime checks after this general preflight succeeds.
The independent [UndefinedBehaviorSanitizer profile](/undefined-behavior-sanitizer.html)
uses the same narrow host and compiler support claim, but has separate build
state, instrumentation proof, canary, runtime contract, and blocking job.

Success means that the environment and repository metadata match the supported
contract. Failure reports all detected missing, unsupported, or drifted
prerequisites before the build begins. The command does not install or download
tools, modify or generate files, clean the checkout, build Dab, or run tests.
Run the [complete validation gate](/complete-validation.html) when the
preflight and inherited build/test/documentation gate should run together.
