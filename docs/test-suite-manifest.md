---
layout: page
title: Test suite manifest
---

The machine-readable test inventory is [`config/test_suites.json`](https://github.com/thomas-pendragon/dablang/blob/master/config/test_suites.json).
Validate it from the repository root with the read-only command:

```shell
bundle exec ruby script/test_suite_manifest.rb
```

The manifest uses schema version `1`. Every suite has a stable ID, one state, a
real command and source glob, and an `in_complete_gate` declaration. Rake suites
also name their real Rake task. The state vocabulary is closed:

- `active` means that the suite has executable repository wiring. Active does
  not imply complete-gate membership; `compiler_performance_spec` is deliberately
  manual, while `address_sanitizer_spec` and
  `undefined_behavior_sanitizer_spec` each have one dedicated manual/CI path.
- `pending` means that evidence is collected but deliberately not executed on
  at least one represented path.
- `disabled` means that repository evidence deliberately excludes the suite or
  fixture group from normal execution. Every pending or disabled entry requires
  a reason.

The separate `exceptions` collection records evidence inside or adjacent to a
suite without representing that suite twice. Each exception has its own stable
ID, a pending or disabled state, a source glob, a reason, and either a source
pattern or an `excluded_from_task` assertion.

## Current executable inventory

The default `bundle exec rake` task reaches these active Rake suites:

- `minitest_spec`;
- `dab_fixture_spec` (the public alias for the generated `dab` task);
- `format_spec`, `vm_spec`, `disasm_spec`, and `asm_spec`;
- `dumpcov_spec`, `cov_spec`, and `debug_spec`;
- `multidab_spec` and `decompile_spec`; and
- `legacy_source_vm_smoke`, the external production source-to-bytecode-to-native-VM
  reproducibility check.

The complete gate runs that default Rake task and then the active standalone
RSpec suite exactly once. The active `compiler_performance_spec` task is manual
and is not in the complete gate. Rake also declares `build_examples_spec`, but
its default-task dependency is explicitly commented out; the manifest therefore
records it as disabled and outside the complete gate.

The active `address_sanitizer_spec` and `undefined_behavior_sanitizer_spec`
tasks are each represented once and remain outside the complete gate. Their
repository-root commands are also the commands used by their independent
blocking Linux x86_64 sanitizer CI jobs.

Current non-active evidence remains recorded without enabling or deleting it:

- RSpec examples declared with `xit` are pending within the active RSpec suite.
- The process-group timeout assertion is pending on Windows, where the harness
  uses its separately exercised `taskkill` path.
- `.dabtx` files under `test/dab/` are disabled by the active `.dabt` glob.
- `.testx` files under `test/multidab/` and `test/decompile/` are disabled by
  those suites' active `.test` globs.

These classifications describe current executable evidence, not planned
language behavior. The manifest does not enable a suite, define semantics, or
freeze example/pass/pending counts.

## Fail-closed validation

The validator parses the JSON and rejects malformed input, wrong object and
container types, unsupported schema/state/kind values, unknown fields, duplicate
IDs, missing commands or Rake tasks, empty or non-portable source globs,
non-active entries without reasons, and invalid gate-membership declarations.
It loads the current Rake task graph without invoking tasks, discovers fixture
suites from their paired forward/reverse tasks, resolves aliases, checks every
manifest glob against actual task inputs, and compares default-task reachability.
It also compares standalone suite commands with the current complete-gate stages
and checks each exception's source evidence. Diagnostics are sorted and paths
use repository-relative forward slashes on every platform.

The [complete validation gate](/complete-validation.html) runs this validator
before the supported-toolchain preflight and expensive test stages. A validator
failure stops immediately and preserves its nonzero exit status. After a
successful validation, the existing preflight, inherited Rake gate, and RSpec
suite retain their order and one-run behavior.

Changing `setup_tests` declarations, direct test Rake tasks, default Rake
dependencies, complete-gate suite stages, suite state, source extensions,
pending markers, or platform skips requires updating the manifest and its
evidence in the same change. Run the manifest validator before the complete
gate so topology drift fails early.
