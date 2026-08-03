# Modern-source fixture format

Files with the exact lowercase `.dabmtest` extension are versioned, single-source
compiler fixtures owned by the `modern_source_spec` Rake task. Each file contains
repository-native `## NAME` sections. The canonical order is required source,
schema version, and status, followed by stdout and stderr only when those exact
expected streams are nonempty:

```text
## SOURCE
future Modern source
## SCHEMA VERSION
1
## STATUS
2
## STDERR
compiler diagnostic followed by a literal newline
```

`SOURCE`, `SCHEMA VERSION`, and `STATUS` are required exactly once. `STDOUT` and
`STDERR` are optional, but an empty output section is invalid: omit it to expect
an empty stream. The parser resolves sections by name, so input order does not
change meaning, while committed fixtures use the canonical order above. The
document must start with a section header. Headers are LF-terminated, begin in
column zero, and use one of the exact uppercase names above; leading or trailing
header whitespace, alternate spelling, duplicate sections, and unknown sections
are schema failures.

A section body starts immediately after its header LF and continues through the
byte before the next column-zero `##` header or through end of file. Body bytes
are not stripped: leading blank lines, trailing spaces, and the LF before a
following header all belong to that body. Therefore no decorative blank line is
inserted between sections. A body line beginning with `##` is section syntax and
must name a supported section. This ownership rule makes source and multiline
stream expectations readable without escaping while preserving their exact
bytes. `SCHEMA VERSION` is the exact decimal integer `1`; `STATUS` is a decimal
integer from `0` through `255`; neither scalar accepts surrounding whitespace or
extra blank lines. One final LF is permitted because it is the scalar section's
owned line ending.

CRLF used to transport the whole fixture is normalized to LF before section
parsing, matching the original harness contract. Lone CR bytes remain body data.
After that transport normalization, source, stdout, and stderr bodies are retained
exactly, so the same committed fixture has one source and expectation contract on
Linux, macOS, and Windows.

Some exact assembly expectations contain significant trailing spaces and a final
blank line inherited from compiler stdout. The path-scoped `.gitattributes`
whitespace rule keeps `git diff --check` meaningful for the rest of the repository
without misclassifying those fixture-owned bytes as formatting defects.

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

The corpus keeps the original parser-entry fixture, adds exact negative
bootstrap fixtures for empty and non-`main` names, parameters, body content,
duplicate declarations, comments, and incomplete input, and locks the exact
successful assembly for the canonical minimal `main`. All fixtures use the
section format; large assembly stdout expectations are literal multiline bodies
rather than escaped strings. The negative fixtures
prove status `2`, empty standard output, exact standard error, stable
fixture-derived filenames, and the shared-scanner location of the first
mismatch. The Rake-owned suite supplies the separately compiled Legacy stdlib
Ring so every fixture reaches the version-0.0.35 bootstrap boundary. This format
still owns compiler results only; it does not run the assembler or VM.

Version 0.0.34 adds one multi-artifact exception that this single-source fixture
schema cannot express: exactly one zero-byte file-backed Modern unit may compile
as an upper Ring layer when a separately compiled lower Ring is supplied. The
end-to-end contract in `spec/modern_legacy_stdlib_ring_spec.rb` compiles the
Legacy standard library, compiles and assembles that empty upper layer twice,
inspects the combined Ring environment, and exercises missing and corrupt lower
artifacts. This does not add another Modern fixture format. The original fixture
remains nonempty and continues to lock the version-0.0.33 entry message and
location.

Version 0.0.35 accepts one additional byte-exact source over that same lower
Ring: `def main`, LF, `end`, LF. `0009_minimal_main.dabmtest` owns its exact
compiler status, assembly stdout, and empty diagnostic stream. The focused
contract in `spec/modern_minimal_main_spec.rb` separately compiles the lower
Legacy stdlib and upper Modern artifact, assembles both, inspects Ring offsets
and method tables, executes the native VM twice, and probes removed, reversed,
and corrupt lower Rings. Its canonical standalone source is
`test/modern_minimal_main/program.dabm`. This is not general `def` parsing and
the body cannot contain statements.

Version 0.0.36 treats one or more LF bytes as a Modern separator run around
that existing declaration. `0010_newline_separators.dabmtest` proves leading
and body blank separator lines compile to the same assembly as the canonical
source. The focused contract also proves trailing separators, an LF-only unit,
and other separator variants remain deterministic. `0011` and `0012` keep a
newline inside the `def main` header and a semicolon fail-closed with exact
source locations; focused coverage does the same for a space-only body line.
The compiler does not normalize CR or CRLF source. Comments, statements,
additional declarations, and every other Modern syntax feature remain
unsupported.

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
profile, or the compiler API. A Modern unit rejected before a supported
Ring/application boundary retains the zero-width entry point. A single
file-backed Modern unit over a lower Ring instead uses the bootstrap scanner and
attributes a mismatch to its first unsupported token or byte. In a mixed
invocation, the first Modern unit in input order still supplies the entry
diagnostic while every input and Ring remain untouched. The zero-byte Ring layer
still constructs no scanner or parser.

Direct `DabProgramStream` construction remains a lower-level Legacy parser-support
validation boundary. It raises `DabUnsupportedSyntaxProfileError` with the
unchanged generic message and no process status or stream. Direct `DabScanner`
construction remains syntax-neutral: it can carry the same Modern source-unit
identity and produce locations, but emits no diagnostic and accepts no grammar.
`DabModernBootstrapScanner` and `DabModernBootstrapParser` build the one exact
bootstrap production directly on that shared cursor without changing
`DabProgramStream`.

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

The inherited reader deliberately remains loose: it trims header names and
bodies, normalizes names for consumers, accepts sections in any order, and does
not reject unknown or repeated names. The Modern fixture boundary reuses the
same column-zero `## NAME` layout but needs a separate strict reader because its
source and compiler streams are byte-exact and its schema is closed.

`Rakefile` discovers exact lowercase `test/modern_source/*.dabmtest` files
through the existing `setup_tests` owner. It supplies the separately compiled
Legacy stdlib Ring, creates `modern_source_spec` and its reverse task, portable
output names under `tmp/`, one completion marker per fixture, and the established
concise reporter boundary. The suite has one
active entry in `config/test_suites.json` and one dependency from the default
Rake task. Therefore the inherited Rake stage, every effective normal CI job,
and the complete gate reach it exactly once. It is not added to the separate
sanitizer tasks because it is a Ruby compiler-fixture contract, not a native
runtime safety claim.
