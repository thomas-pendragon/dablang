# Modern-source fixture format

Files with the exact lowercase `.dabmtest` extension are versioned, single-source
compiler fixtures owned by the `modern_source_spec` Rake task. Each file contains
repository-native `## NAME` sections. The canonical order is required source,
schema version, and status, followed by compiler stdout and stderr only when
those exact expected streams are nonempty. A successful fixture may then add
`APPLICATION STDOUT` to opt into assembly and native execution:

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

`SOURCE`, `SCHEMA VERSION`, and `STATUS` are required exactly once. `STDOUT`,
`STDERR`, and `APPLICATION STDOUT` are optional, but an empty output section is
invalid: omit it to expect an empty compiler stream or no application run.
`APPLICATION STDOUT` requires status `0` and a `STDOUT` assembly expectation.
The parser resolves sections by name, so input order does not change meaning,
while committed fixtures use the canonical order above. The
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
After that transport normalization, source, compiler streams, and application
stdout bodies are retained exactly, so the same committed fixture has one source
and expectation contract on Linux, macOS, and Windows.

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
bootstrap fixtures for empty and non-`main` names, body content,
duplicate declarations, comment-marker near misses, and incomplete input, and
locks the exact successful assembly for the canonical minimal `main`. All
fixtures use the section format; large assembly stdout expectations are literal
multiline bodies rather than escaped strings. The negative fixtures
prove status `2`, empty standard output, exact standard error, stable
fixture-derived filenames, and the shared-scanner location of the first
mismatch. The Rake-owned suite supplies the separately compiled Legacy stdlib
Ring so every fixture reaches the version-0.0.35 bootstrap boundary. Compiler
results remain the default boundary. A fixture with `APPLICATION STDOUT`
additionally assembles its already-matched compiler output, executes the native
VM over that Ring, requires successful exit, and compares application output
byte-for-byte.

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
and other separator variants remain deterministic. `0011` keeps a newline
inside the `def main` header fail-closed with an exact source location. The
compiler does not normalize CR or CRLF source.

Version 0.0.38 lets the same separator runs contain LF, semicolon, or both.
Runs remain limited to the existing leading, trailing, and empty-body positions,
and the required separators after `main` and `end` may each be semicolons.
`0012_semicolon_separator.dabmtest` covers repeated and mixed runs around and
within the declaration while retaining the canonical assembly exactly. `0013`
proves that semicolon does not replace the header space, and `0014` proves that
it does not make body content valid. Focused coverage also locks single and
repeated semicolons, the exact `def main;end;` framing, separator-only sources,
declaration spans, and per-token coordinates where only LF advances the line.
At version 0.0.38, comments, statements, additional declarations, and every
other Modern syntax feature remain unsupported.

Version 0.0.39 admits exact `#` and `//` line-comment tokens only within those
same separator runs. `0007_comment.dabmtest` proves both markers around and
inside the existing empty declaration, including bodies that contain the other
marker and semicolons, while retaining the canonical assembly exactly. `0015`
keeps a single `/` fail-closed, and `0016` proves that a comment marker cannot
split the required `main` identifier. Focused scanner/parser coverage also
locks marker equivalence, comment-only sources, EOF termination, arbitrary
non-LF body bytes, separate LF tokens, exact comment spans and locations, and
rejection of CR/CRLF structural separators, body statements, and second
declarations. Comments remain separator syntax rather than general whitespace.

Version 0.0.41 admits basic single-line double-quoted Strings only as literal
entries in the existing single-`main` body. Source bytes between the delimiters
must be valid UTF-8 and cannot contain NUL, LF, or CR. Exactly `\"`, `\n`, and
`\r` are decoded; every other backslash sequence fails closed. The unescaped
`#{` opener is reserved and rejected at the marker because interpolation is a
later roadmap row. `0023_basic_strings.dabmtest` covers empty, plain UTF-8, and
all three accepted escapes while preserving the existing assembly. `0024`
through `0026` lock representative unknown-escape, reserved-interpolation, and
physical-newline diagnostics. Focused contracts cover invalid UTF-8, NUL, CR,
unterminated delimiters, doubled backslashes, exact byte spans, transactional
failure, and the reused Legacy String AST, assembly, bytecode, and runtime path.
Legacy parsing remains unchanged.

Version 0.0.42 replaces the generic parser fallback only when the existing
scanner can attribute a rejected form to an already implemented Modern literal.
Exact invalid spellings of `nil`, `true`, and `false`, unsupported numeric
forms, integer overflow, and invalid bytes or markers inside an opened String
now receive concise literal-specific errors at the same offending byte or
marker. `0018`, `0019`, `0021`, `0022`, and `0024` through `0026` lock the
representative compiler diagnostics. Signs remain future operator syntax, and
identifiers, calls, bindings, control flow, adjacent Strings, single quotes,
and every other unimplemented grammar form retain the generic parser fallback.
Accepted Modern output and all Legacy behavior remain unchanged.

Version 0.0.44 replaces the generic parser fallback with structural diagnostics
only after the parser recognizes an invalid state of the implemented
fixed single-`main` shell. `0002`, `0008`, `0011`, and `0013` plus `0028`
through `0032` cover missing fixed-header tokens, required separators, missing
closing `end`, and leading `end`. Focused parser/compiler contracts additionally
cover zero-width EOF attribution, extra `end`, lone CR, and a two-byte CRLF
scanner span. CRLF cannot be represented as source data in this fixture format
because transport normalization deliberately converts every CRLF pair to LF;
lone CR remains representable but is covered beside CRLF in the byte-exact
focused contract. Other function names, parameters, return annotations,
identifiers, expressions, calls, operators, extra declarations, trailing forms,
and all later grammar retain the generic parser fallback. This row changes no
accepted Modern or Legacy source, output, Ring, bytecode, or runtime behavior.

Version 0.0.46 activates general names and multiple declarations within that
closed shell. A document may contain zero or more distinct no-argument
top-level declarations. Callable names use the Original #36 ASCII identifier
boundary with an optional adjacent `?` or `!`; `def`, `end`, `nil`, `true`, and
`false` remain reserved. Bodies remain limited to the existing literal set and
the established LF, semicolon, and line-comment separators. Every closing
`end`, including the last one in the file, still requires a following
separator. Fixtures `0003`, `0033`, and `0034` now lock successful plain and
suffixed declarations. Fixtures `0035` and `0036` lock the same three
declarations in both source orders and prove deterministic sorted assembly.

The compiler parses the complete document and preflights all names before it
adds a function. Same-document duplicates, builtins, and lower-Ring functions
reject transactionally with the generic diagnostic at the complete colliding
name. `0006` locks the same-document compiler boundary, while focused contracts
cover all three collision classes, complete-document precedence, composite
spans, source order, lowering, and the uniform function-level structural
diagnostics. Parameters, return contracts, calls, dot calls, statements,
bindings, control flow, types, operators, nested declarations, top-level values,
overload or replacement rules, forward-reference behavior, and formatter
support remain outside this grammar.

Version 0.0.47 accepts optional typed parameter clauses and return contracts on
those declarations. Bare zero-parameter headers and explicit empty `()` are
both valid. ASCII spaces and TABs are optional and repeatable around
parentheses, commas, colons, parameters, and the return contract; LF and
comments retain their separator role, while CR and CRLF remain invalid.
`0004_parameters.dabmtest` now locks the explicit-empty compatibility form,
`0037` locks an excluded type diagnostic, and `0038` locks typed parameter and
return metadata in successful assembly.

The accepted type spellings are exactly `String`, `Fixnum`, `Boolean`,
`Uint8`, `Uint16`, `Uint32`, `Uint64`, `Int8`, `Int16`, `Int32`, `Int64`,
`IntPtr`, `NilClass`, and `Float`. Focused contracts cover ordered AST and
metadata lowering, all nine contextual diagnostic families, exact spans,
duplicate names, unknown and excluded types, complete-document and pre-Ring
transactionality, assembly, bytecode metadata, native loading, and unchanged
callable collision behavior. Calls, dot calls, body parameter references,
bindings, statements, defaults, generics, variadics, keyword invocation,
inference, overloads, aliases, nominal types, Modern formatting, and new
bytecode or runtime invocation behavior remain deferred.

Version 0.0.48 adds direct calls as body items without introducing a general
expression grammar. Calls accept only the existing literal families as
arguments, use optional ASCII space or TAB around their punctuation, require an
immediate LF, semicolon, or line-comment body separator, and discard their
results through the existing `RNIL` path. Fixture `0039` locks the unknown-call
diagnostic after a complete direct-call parse. Same-document functions support
forward calls and recursion with exact arity and current assignability checks;
`print` remains variadic; and free lower-Ring `puts` is accepted only when its
artifact metadata confirms the exact one-argument `Object` signature. Every
other builtin, Ring function, class or method, internal syscall, unsafe target,
and FFI-adjacent target remains unsupported. Focused contracts own the five
syntax and four semantic diagnostic families, exact spans, transactional
preflight, suffix targets, existing assembly, and native execution. Nested
calls, result use, body references, dot/property calls, bindings, statements,
operators, and all later expression rows remain deferred.

Fixture `0040` supplies the positive core-suite execution contract for this
row. It calls variadic builtin `print` with one existing String literal, retains
the exact compiler assembly expectation, and opts into the normal harness's
successful native application-output comparison. The detailed RSpec coverage
remains supplementary rather than the sole positive runtime proof.

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

Original #36 added only lexical infrastructure. Outside Strings and comments,
the scanner emits one-byte `question_mark` and `bang` tokens. A contextual
callable-name helper can compose zero or one immediately adjacent suffix while
retaining the base, suffix, and composite source spans. Fixtures `0033` and
`0034` proved that row still rejected suffixed `main` declarations with the
same generic diagnostic, status, streams, and suffix location. Version 0.0.46
now activates that declaration-name slot only; call and selector rows remain
responsible for their separate grammar positions.

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
Legacy stdlib Ring and native VM, creates `modern_source_spec` and its reverse
task, portable output names under `tmp/`, one completion marker per fixture, and
the established concise reporter boundary. The suite has one
active entry in `config/test_suites.json` and one dependency from the default
Rake task. Therefore the inherited Rake stage, every effective normal CI job,
and the complete gate reach it exactly once. It is not added to the separate
sanitizer tasks because its optional native execution is a language-result
contract over trusted generated artifacts, not a malformed-input safety claim.
