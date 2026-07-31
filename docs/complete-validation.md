---
layout: page
title: Complete validation gate
---

From the repository root, run the complete validation gate with:

```shell
ruby script/complete_gate.rb
```

The command runs these stages once and in this order:

1. read-only [test suite manifest validation](/test-suite-manifest.html);
2. supported-toolchain preflight;
3. the inherited `bundle exec rake` build, fixture-test, and documentation
   gate, including the reproducible [legacy source-to-VM smoke](/legacy-source-vm-smoke.html)
   exactly once and without omitting any of its current tasks; and
4. the Ruby RSpec suite (`bundle exec rspec`).

Each stage is announced before it runs. Failures stop the command immediately,
preserve the failing stage's exit code, and leave its diagnostics visible. The
CI workflow invokes this one entrypoint for every Linux, macOS, and Windows
run.

The manifest validator runs before the preflight and expensive validation. Use
`bundle exec ruby script/test_suite_manifest.rb` to run that topology check by
itself. After it succeeds, the preflight, inherited Rake gate, and RSpec suite
keep their existing order and one-run behavior.

The command supports the same Linux, macOS, and Windows environments as the
preflight. Set `PREMAKE` and `CLANG_FORMAT` when the supported tools are not on
`PATH`, as described in the [supported toolchain preflight](/toolchain-preflight.html).

The inherited Rake gate owns `docs/vm/opcodes.md`, `docs/classes.md`, and every
page under `docs/classes/`. These generated files do not embed checkout time or
revision metadata, so their contents depend only on their source definitions.
The complete gate rejects pre-existing tracked changes to these paths before
preflight, then checks after each successful stage that validation did not
change them. A failure lists every changed generated-documentation path in
deterministic order. Untracked build artifacts and tracked files outside these
owned paths are ignored by this check.

A clean checkout with current generated documentation can therefore run the
complete gate in place. When an intentional source or generator change updates
the owned documentation, regenerate and review the outputs, commit them with
the source change, and rerun the complete gate. A failing build, test, or
documentation stage keeps its original nonzero exit status even if it also
changes generated documentation.

Use `bundle exec rake spec` for the Ruby RSpec suite alone. The inherited Dab
fixture suite remains available as `bundle exec rake dab_fixture_spec` and is
still part of both `bundle exec rake` and the complete validation gate.

Fixture and VM tests keep successful output concise by default: each selected
test reports a pass status and each suite reports a completion summary, while
compiler, assembler, VM, and diagnostic details are retained for failures. To
inspect the detailed output for successful tests, set the explicit opt-in
environment variable:

```shell
DAB_TEST_VERBOSE=1 bundle exec rake dab_fixture_spec
```

Failure reports include the test identity, stage, command, exit status, and
captured stdout/stderr. This is scoped to the test harness; setup, build, CI,
warnings, selection, ordering, and command exit statuses remain visible and
unchanged.

The fixture frontends already declare their subprocess limits through the
existing `qsystem(..., timeout: seconds)` calls (30 seconds for Ruby compiler
actions and 10 seconds for native tools and VM actions). These limits are
enforced per action using monotonic elapsed time. A timeout terminates the
command process tree, fails the harness with exit status 124, and replays the
test identity, stage, command, configured limit, and `timed out` outcome with
the captured diagnostics. Tests without a declared timeout keep their existing
unbounded behavior.

The legacy source-to-VM smoke is also available directly as:

```shell
bundle exec rake legacy_source_vm_smoke
```

Its Rake dependency builds the platform-native VM before two independent
external compiler, assembler, and VM runs. The smoke uses its own stage limits;
it does not alter the fixture harness limits above.

The dedicated [AddressSanitizer validation](/address-sanitizer.html) remains an
active manual and CI suite outside this ordinary complete gate. Keeping it in a
single Linux x86_64 job avoids multiplying the native sanitizer build through
the Ruby and operating-system matrix.
