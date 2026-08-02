# Modern-source fixture format

Files with the exact lowercase `.dabmtest` extension are versioned, single-source
compiler fixtures owned by the `modern_source_spec` Rake task. Each file contains
one JSON metadata object, one exact `--- SOURCE ---` delimiter line, and the raw
Modern source after that delimiter:

```text
{
  "schema_version": 1,
  "status": 2,
  "stdout": "",
  "stderr": "compiler diagnostic followed by an escaped newline\n"
}
--- SOURCE ---
future Modern source
```

Schema version `1` allows exactly four metadata fields. `status` is the expected
compiler exit status from `0` through `255`; `stdout` and `stderr` are exact
expected strings, including every newline represented by JSON escapes. Missing,
unknown, or mistyped fields are fixture-schema failures. CRLF used to transport
the fixture is normalized to LF before parsing so the same committed fixture has
one source and expectation contract on Linux, macOS, and Windows.

The source becomes one extracted `.dabm` input. Its stable diagnostic filename is
the fixture basename with `.dabmtest` replaced by `.dabm`. The harness constructs
a `DabSourceUnit` with that filename and the canonical
`DabSyntaxProfile::MODERN`; it does not rely on filename inference, a CLI option,
or mutable profile state. Compiler status, stdout, and stderr are then compared
exactly. A nonzero compiler status is a passing negative fixture when all three
expectations match.

Fixture-schema errors use `DabModernSourceFixture::SchemaError` and name the
fixture plus the invalid field or boundary. Valid fixtures that observe a
different compiler result use `DabModernSourceExpectationError` and name the
mismatched status or stream. The shared Dab reporter keeps successful fixtures
concise, shows action details under `DAB_TEST_VERBOSE=1`, and replays attributed
per-fixture details on failure.

The initial fixture proves only the existing deterministic unsupported-Modern
boundary. Modern tokens, grammar, diagnostic design, AST/IR, code generation,
and runtime behavior remain unimplemented and outside this format contract.

## Owned harness boundary

The inherited fixture formats remain unchanged. Their shared loose section
reader powers `.dabt` source-to-VM fixtures (`CODE`, successful output, compiler
failure substring, or runtime failure substring), `.dabft` formatter
input/output fixtures, and the assembly, VM, disassembly, coverage, debug,
multilevel Ring, and decompile formats. The new `.dabmtest` parser does not
reinterpret those sections or change their source, expected-output,
expected-failure, option, platform-library-extension, or path behavior.

`Rakefile` discovers exact lowercase `test/modern_source/*.dabmtest` files
through the existing `setup_tests` owner. That creates `modern_source_spec` and
its reverse task, portable output names under `tmp/`, one completion marker per
fixture, and the established concise reporter boundary. The suite has one
active entry in `config/test_suites.json` and one dependency from the default
Rake task. Therefore the inherited Rake stage, every effective normal CI job,
and the complete gate reach it exactly once. It is not added to the separate
sanitizer tasks because it is a Ruby compiler-fixture contract, not a native
runtime safety claim.
