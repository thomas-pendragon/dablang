---
layout: page
title: Complete validation gate
---

From the repository root, run the complete validation gate with:

```shell
ruby script/complete_gate.rb
```

The command runs these stages once and in this order:

1. supported-toolchain preflight;
2. the inherited `bundle exec rake` build, fixture-test, and documentation
   gate, without omitting any of its current tasks; and
3. the Ruby RSpec suite (`bundle exec rspec`).

Each stage is announced before it runs. Failures stop the command immediately,
preserve the failing stage's exit code, and leave its diagnostics visible. The
CI workflow invokes this one entrypoint for every Linux, macOS, and Windows
run.

The command supports the same Linux, macOS, and Windows environments as the
preflight. Set `PREMAKE` and `CLANG_FORMAT` when the supported tools are not on
`PATH`, as described in the [supported toolchain preflight](/toolchain-preflight.html).

The inherited Rake gate can regenerate tracked documentation. Run the complete
gate in a disposable checkout when those generated-file changes must not affect
your working tree.

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
