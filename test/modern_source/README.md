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

The diagnostic corpus contains one compiler fixture because every non-empty
Modern source currently reaches the same syntax-neutral parser-entry rejection.
Adding source content variants would duplicate that observable contract. The
fixture proves
status `2`, empty standard output, and exact standard error including its stable
fixture-derived filename and zero-width entry location at offset `0`, line `1`,
column `0`. Modern tokens, grammar, AST/IR, code generation, and runtime behavior
remain unimplemented and outside this format contract.

Version 0.0.34 adds one multi-artifact exception that this single-source fixture
schema cannot express: exactly one zero-byte file-backed Modern unit may compile
as an upper Ring layer when a separately compiled lower Ring is supplied. The
end-to-end contract in `spec/modern_legacy_stdlib_ring_spec.rb` compiles the
Legacy standard library, compiles and assembles that empty upper layer twice,
inspects the combined Ring environment, and exercises missing and corrupt lower
artifacts. This does not add another Modern fixture format. This fixture remains
non-empty and continues to lock the exact version-0.0.33 diagnostic for all
Modern content.

## Diagnostic boundary

Before the source-attributed diagnostic contract, inferred `.dabm`, explicit
`--syntax=modern`, the
per-source-unit compiler API, and mixed Legacy/Modern compiler invocations all
returned status `2`, empty standard output, and exactly
`compiler: unsupported Dab syntax profile "modern": parser is not implemented`
plus a newline. The frontend retained the selected `DabSourceUnit`, but the
diagnostic exposed no filename or location. Validation happened before reading
any input, loading a Ring, constructing a scanner or parser, or compiling an
earlier Legacy unit. Input order therefore had no visible effect on the generic
message.

The source-attributed contract keeps the same status, streams, message text, and
no-input-read transaction boundary, but adds the first unsupported source unit's
portable filename and the syntax-neutral entry location:

```text
compiler: SOURCE.dabm:1:0: error: unsupported Dab syntax profile "modern": parser is not implemented
```

`DabModernSyntaxDiagnosticError` carries a `DabSourceLocation` whose source unit
is the exact frozen object selected by filename inference, an explicit CLI
profile, or the compiler API. Its location is a zero-width frontend entry point;
it is not evidence that a token was scanned. In a mixed invocation, the first
Modern unit in input order supplies the diagnostic identity while every input,
Ring, scanner, Legacy parser, and compiler remain untouched. The separately
specified zero-byte Ring-layer path inspects only the empty byte boundary and
constructs no scanner or parser.

Direct `DabProgramStream` construction remains a lower-level parser-support
validation boundary. It raises `DabUnsupportedSyntaxProfileError` with the
unchanged generic message and no process status or stream. Direct `DabScanner`
construction remains syntax-neutral: it can carry the same Modern source-unit
identity and produce locations, but emits no diagnostic and accepts no grammar.

Fixture schema failures remain separate and happen before
`DabModernSourceCompiler` is constructed. A valid schema always reaches the
compiler and a result mismatch raises `DabModernSourceExpectationError` only
after exact status, stdout, and stderr capture. The reporter's concise success,
verbose action detail, and attributed failure replay behavior is unchanged.

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
