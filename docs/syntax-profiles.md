---
layout: page
title: Syntax profiles
---

# Syntax profiles

The source parser has one explicit, finite syntax-profile model. Every compiler
input becomes a frozen `DabSourceUnit` that retains its input identity,
diagnostic filename, and canonical `DabSyntaxProfile` through
`DabProgramStream` construction. This is per-source-unit data, not mutable
process-global, class-global, environment, thread-local, or invocation-global
state.

The registered identities are `DabSyntaxProfile::LEGACY` and
`DabSyntaxProfile::MODERN`. General Modern grammar is not implemented: Modern
content outside the narrow Ring-layer grammar described below fails rather
than being sent through the legacy parser. Compiler frontends report a Modern
unit rejected before bootstrap scanning at the zero-width entry location
(offset `0`, line `1`, column `0`).
Direct callers can provide a complete source unit:

```ruby
source_unit = DabSourceUnit.new(
  input: 'program.dab',
  syntax_profile: DabSyntaxProfile::LEGACY
)
DabProgramStream.new(source, source_unit: source_unit)
```

Omitting both `source_unit:` and `syntax_profile:` when constructing a program
stream or compiler frontend still derives one canonical Legacy source unit for
practical single-source compatibility. An explicit compiler API invocation can
also force Legacy across its input list without adding a command-line option:

```ruby
run_dab_compiler(settings, context,
                 syntax_profile: DabSyntaxProfile::LEGACY)
```

`DabSyntaxProfile.fetch('legacy')` and `DabSyntaxProfile.fetch('modern')`
return their canonical frozen identities. Unknown names raise
`DabSyntaxProfileError`, and parser or frontend construction rejects strings,
symbols, booleans, `nil`, and other unregistered values rather than guessing or
falling back. A `DabProgramStream` given the canonical Modern identity raises
`DabUnsupportedSyntaxProfileError` before consuming source. This lower-level
boundary retains the generic exception without adding a compiler-formatted
filename or location.

## Compiler command line

The shipped compiler accepts one optional syntax selection in its exact equals
spelling:

```text
ruby src/compiler/compiler.rb --syntax=legacy SOURCE
```

`--syntax=legacy` may appear before or after source paths, as other existing
compiler options may. The compiler removes that command-line option before its
normal argument parser sees inputs, resolves `legacy` with
`DabSyntaxProfile.fetch`, and passes the resulting canonical profile to every
compiler source unit. Omitting the option remains byte-for-byte
compatible with the legacy fallback.

The separated spelling `--syntax legacy` is not supported. Supplying it, or
supplying `--syntax` without `=PROFILE`, exits with status 2 and the stable
diagnostic `compiler: --syntax requires the --syntax=PROFILE spelling`.
Repeated syntax options exit with status 2 and `compiler: --syntax may be
specified at most once`. Empty and unknown values, including `--syntax=` and
`--syntax=future`, exit with status 2 using the canonical unknown-profile
diagnostic. `--syntax=modern` resolves the canonical identity. Standard input
and invocations without a Ring base still exit with status `2`, empty standard
output, and
`compiler: SOURCE:1:0: error: unsupported Dab syntax profile "modern": parser is
not implemented` on standard error. Standard input uses the established
`<input>` diagnostic filename.

When no syntax option is explicit, exact lowercase `.dab` selects
`DabSyntaxProfile::LEGACY` and exact lowercase `.dabm` selects
`DabSyntaxProfile::MODERN`. Modern selection then produces the stable
unsupported-parser diagnostic above unless it meets the exact zero-byte
Ring-layer contract below. An explicit option takes precedence over filename
inference, so
`--syntax=legacy FILE.dabm` intentionally remains a forced legacy parse.
Standard input, uppercase `.DAB` or `.DABM`, and other unrecognized filename
extensions retain the existing canonical legacy fallback.

Without an explicit option, each source unit selects its profile independently.
Mixing `.dab` and `.dabm` therefore no longer fails merely because the profiles
differ: the `.dab` unit retains Legacy and the `.dabm` unit retains Modern,
regardless of input order. The empty Ring-layer allowance requires exactly one
Modern source unit, so a mixed upper source list still fails transactionally
with status 2 and the stable source-attributed unsupported-Modern diagnostic.
No Legacy input is partially parsed or compiled first. With `--syntax=legacy`
or `--syntax=modern`, the selected canonical identity is instead assigned to
every source unit before the same validation.

## Empty Modern application over a Legacy Ring

The compiler accepts exactly one file-backed Modern source unit only when its
retained content is exactly zero bytes and at least one `--ring-base[]=PATH` is
present. The intended lower input is the existing `tmp/stdlib.dabcb` artifact,
which `src/frontend/frontend_stdlib.rb` produces by compiling the repository's
`stdlib/*.dab` sources through the Legacy frontend and assembling the result.
The standard library therefore remains Legacy source and a separately compiled
Ring; it is not reparsed or reclassified as Modern.

The frontend checks the zero-byte boundary before loading a Ring, loads each
lower compiled Ring through the existing `DabBinReader` path, reads the source,
and checks the retained bytes again before compilation. It does not construct a
`DabScanner`, `DabProgramStream`, Legacy parser, Modern parser, AST, or IR for the
empty unit. The canonical `DabSourceUnit` continues to retain
`DabSyntaxProfile::MODERN` throughout the invocation.

Compilation emits the normal deterministic upper Ring layer. Its DAB header
offset equals the byte length of the lower Ring, and its symbol/class/method
environment comes from the parsed lower artifact. The existing compiler may
regenerate upper metadata such as class records and the offset-derived
initialization function, but it does not copy the lower code or data sections.
The upper artifact is not a standalone flattened image: consumers must keep the
existing lower-then-upper Ring order. The DAB format, snapshot writer, loader,
VM, and trusted-local artifact boundary are unchanged.

Removing the lower Ring makes the empty Modern unit unsupported again. A
malformed lower artifact still fails through the existing Ring reader, and a
different lower artifact changes the upper offset or available environment.
Any nonzero source not matching the exact minimal-main production below retains
the status-2 source-attributed diagnostic from version 0.0.33. Standard input, a
missing file, more than one upper source unit, and an empty Modern file without
a Ring base also retain that rejection.

## Minimal Modern main over a Legacy Ring

Version 0.0.35 accepts one additional Modern upper Ring. Its file content must
be exactly these bytes, including LF after both lines and no other byte:

```text
def main
end
```

A dedicated bootstrap scanner and parser, built on `DabScanner`,
`DabSourceLocation`, and `DabSourceSpan`, recognize the six structural tokens:
`def`, one ASCII space, the exact ASCII identifier `main`, LF, `end`, and final
LF. The structural LFs are part of this single production; they do not establish
general newline-as-statement-separator semantics. A typed bootstrap declaration
lowers into the existing `DabNodeFunction` boundary with no arguments and an
empty body. Existing compiler passes add the implicit Nil return, so the emitted
`main` method contains `RETURN RNIL` and no application output or warning call.

The same application boundary as the zero-byte case applies: exactly one
file-backed Modern source and at least one lower Ring are required. The intended
lower Ring is the separately compiled Legacy standard library. The upper header
offset equals the lower artifact's byte length, and the upper artifact contains
the callable `main` method without flattening lower code, data, classes, or
stdlib functions. The existing VM must receive the lower Ring before the upper
Ring. A successful run exits with process status 0 and writes exactly zero bytes
to the application channel selected by `--out=PATH`.

Raw process stderr is not the application stderr channel. The current VM writes
loader, startup, initialization, and teardown diagnostics there on successful
runs. The end-to-end contract captures that stream separately and accepts only
the characterized line categories in their exact order; unexpected lines,
application warnings, errors, and sanitizer reports fail the contract.

At version 0.0.35 this was not general `def` parsing. It accepted no other
function name, additional declaration, parameter or parentheses, return
annotation, statement, literal, call, variable, type, comment, semicolon,
leading or trailing token, CR-only line ending, CRLF line ending, or missing
final LF. Later separator versions extend only the positions described below.
Other near misses retain the version-0.0.33 message and are attributed to the
first mismatching location from the shared scanner. General definitions and
body statements remain later roadmap work.

## Modern newline separators

Version 0.0.36 gives the existing LF token one syntax meaning: one or more LF
bytes form a Modern statement-separator run. Separator runs may appear before
or after the currently supported top-level declaration and as blank lines in
its empty body. A source containing only LF separators is equivalent to the
already supported zero-byte Modern upper unit. The canonical 0.0.35 source
remains accepted without changes and compiles to the same upper assembly and
runtime behavior.

The `def main` header and its closing `end` must each be followed by at least
one LF separator. The declaration span still starts at `def` and ends after the
first LF following `end`; leading and additional trailing separators are not
part of the declaration. Every separator retains its shared-scanner offset,
line, column, source-unit identity, and half-open span.

In version 0.0.36 only byte `0x0a` is a separator. ASCII spaces do not make a
blank separator line, and CR or CRLF input is not normalized by the compiler.
Comments, body content, additional declarations, literals, calls, variables,
types, and general function parsing remain rejected at the first mismatching
scanner location. Because the current subset has no body statement, this
version establishes blank-line and empty-unit separator behavior without
inventing a statement production.

## Modern semicolon separators

Version 0.0.38 adds byte `0x3b` (`;`) as the alternative token accepted by the
same separator abstraction. One or more LF or semicolon tokens, in any mix,
form a separator run only where the version-0.0.36 grammar already accepted an
LF run: before or after the single supported declaration, within its empty
body, and throughout a separator-only source. The required separators after
the `def main` header and after `end` may also be semicolons, so
`def main;end;` is the smallest semicolon-framed declaration. The canonical
0.0.35 source and every 0.0.36 LF-only form remain accepted and compile to the
same upper assembly and runtime behavior.

A semicolon remains syntax rather than whitespace. The scanner emits each one
as its own token with its exact offset, line, column, half-open span, and source
unit. It consumes one column and does not advance the line; only LF changes line
coordinates. The declaration span still starts at `def` and ends after the
first separator following `end`, whether that separator is LF or semicolon.
Leading separators and every additional trailing separator remain outside the
declaration span.

Semicolon does not replace the required ASCII space between `def` and `main`,
split or join an identifier or keyword, permit content in the empty body, or
separate another declaration. Those shapes fail at the first mismatching
scanner token. At version 0.0.38, spaces, CR, CRLF, comments, statements,
additional declarations, literals, calls, variables, types, and general
function parsing remain unsupported.

## Modern line comments

Version 0.0.39 originally added two exact line-comment markers: byte `0x23`
(`#`) and the two-byte sequence `0x2f 0x2f` (`//`). The scanner emitted one
`line_comment`
token containing the marker and every following non-LF byte. The token ends
immediately before the next LF or at EOF. It never consumes the LF: that byte
remains its own `line_feed` token with the shared scanner's existing offset,
line, column, and half-open span.

A line comment is admitted only as another member of the existing separator
abstraction. Comments may therefore appear in separator runs before or after
the one supported empty `main` declaration, between its header and `end`, or
throughout a separator-only source. A comment may be the required first
separator after `main` or `end`, including an EOF-terminated comment, so
`def main# header\nend# trailing` is accepted without treating any ordinary
space as trivia. If the first separator after `end` is a comment, the
declaration span ends at that comment's half-open end; a following LF and later
separators remain outside the declaration.

As of version 0.0.84, `#` is the only Modern line-comment marker. Its body is
opaque and may contain `//`, more copies of `#`, semicolons,
spaces, tabs, NUL, CR, or any other non-LF byte. In particular, CR inside a
comment body remains ordinary body data rather than a line ending; this does
not normalize or accept CR or CRLF at structural separator positions.

This is not general whitespace or token-internal comment support. A comment
marker cannot split or join `def`, `main`, `end`,
or another identifier, and an ASCII space before a marker remains invalid
where the prior grammar did not accept a space. Comments do not permit a body
statement, a second declaration, a literal, an operator or division, a call,
a variable, a type, a general function, or any later Modern production.

## Modern regular-expression source lexing

Version 0.0.84 reserves slash-delimited regular-expression source only at an
existing parser-declared value entry. The grammar is `/`, zero or more raw body
items, then `/`. A body item is either backslash plus exactly one non-line-ending
byte or one byte other than slash, backslash, LF, or CR. The empty `//` form is
therefore a valid source lexeme in value mode. Backslash affects delimiter
finding only: body bytes, escapes, `#`, interpolation-like text, NUL, and invalid
UTF-8 remain raw and undecoded. Apparent flags are subsequent identifier tokens.

The scanner freezes opening, body, and closing source tokens, their shared source
unit and half-open spans in `DabModernBootstrapRegexLiteralSource`; an empty body
has a zero-width span. The outer `regex_literal` token covers the complete
lexeme. Raw LF, CR, and CRLF, escaped line endings, EOF without a closer, and an
EOF-trailing backslash each have a byte-exact diagnostic span.

This row does not admit an executable literal. Every well-formed candidate is
rejected across its full span because runtime Regex construction belongs to
EX-010 and executable admission belongs to OR-057. The token is not a literal or
value kind and has no lowering path. In ordinary mode each slash remains an
independent one-byte unsupported token, so `//` is never a separator or comment
and is never swallowed to LF or EOF. Boolean conditions, postfix guards, `when`
patterns, headers, separator positions, and the position after a completed
value remain ordinary mode. Legacy slash division and `//` comments are
unchanged.

## Modern top-level function declarations

Version 0.0.46 generalizes the established fixed `def main ... end` shell to a
complete document containing zero or more distinct, no-argument top-level
function declarations. A callable name is the existing ASCII identifier plus
zero or one immediately adjacent `?` or `!`. The scanner reserves only the
already established `def`, `end`, `nil`, `true`, and `false` tokens; other
identifier spellings are eligible callable names.

Each header still requires exactly one ASCII space after `def` and one LF,
semicolon, or line-comment separator after its callable name. Each body remains
limited to the already implemented Nil, Bool, nonnegative integer, and String
literals, with an established separator after every literal. A closing `end`
and a separator after that `end` are mandatory for every declaration, including
the final declaration at end of file. Leading, inter-declaration, and trailing
separator runs remain accepted. CR and CRLF remain invalid structural
separators.

The parser consumes the complete document before lowering. It then checks every
composite callable name before adding any function. A duplicate in the same
document, a builtin collision, or a function already supplied by a lower Ring
rejects the source transactionally with the generic Modern parser diagnostic at
the full colliding name span. Distinct plain, `?`, and `!` names do not collide.
After this preflight, declarations lower through the existing function and
literal AST path. Compiler sorting keeps assembly, bytecode, and runtime symbol
order deterministic independently of declaration order; suffixes retain the
established `%QUEST` and `%BANG` assembly spelling.

This version adds no parameters, return annotations, calls, dot calls,
statements, bindings, control flow, types, operators, nested declarations,
top-level values, overload or replacement rule, forward-reference behavior, or
formatter support. The assembler, bytecode format, VM, runtime semantics, and
Legacy parser remain unchanged.

## Current construction paths

| Consumer | Parser construction | Current profile contract |
| --- | --- | --- |
| Production compiler frontend | One `DabSourceUnit` per input; shared `DabScanner` and `DabProgramStream` for Legacy parsing, plus the narrow Modern bootstrap scanner/parser | An explicit `--syntax=PROFILE` applies to every unit. Otherwise, each unit independently infers Legacy from exact `.dab` or Modern from exact `.dabm`; standard input and unrecognized extensions derive the Legacy fallback. The zero-byte Modern Ring layer bypasses scanner/parser construction. Supported Modern declarations use only the closed bootstrap grammar above; every other Modern boundary rejects. |
| Modern-source fixture harness | One extracted source and explicit `DabSourceUnit` per `.dabmtest` fixture, compiled over the Legacy stdlib Ring | The harness always passes `DabSyntaxProfile::MODERN` through the source-unit API, derives a stable `.dabm` diagnostic filename, and exactly compares expected compiler status, stdout, and stderr. Bootstrap mismatches retain that exact source identity and shared-scanner location. It does not infer or mutate profile state, assemble artifacts, or run the VM. |
| Source formatter and format fixtures | One direct `DabProgramStream` | These practical single-source callers derive a Legacy source unit through the parser API compatibility default. |
| Assembler and decompiler assembly reader | `DabParser` | These consume assembly text through lower-level scanner helpers, not a Dab source-syntax profile. |
| Parser specifications and direct Ruby callers | `DabProgramStream` | Callers can pass `source_unit:` to preserve a complete input identity or `syntax_profile:` to derive one. Omitting both remains a narrow single-source Legacy compatibility path. Passing both is rejected rather than guessing precedence. |

## Shared scanner and source locations

`DabScanner` is the syntax-neutral cursor and location boundary below the
existing `DabParser`. The production Legacy `DabProgramStream` uses that
scanner through inheritance; the scanner is not an unused Modern-only API.
Every scanner receives one frozen `DabSourceUnit`, and every location and span
retains that exact source-unit object and therefore its filename and canonical
syntax profile. A scanner may carry a Modern source unit, and the minimal-main
bootstrap scanner now reuses this boundary. `DabProgramStream` still rejects
Modern before any Legacy token rule runs.

`DabSourceLocation` is a frozen value containing the source unit, offset, line,
and column. `DabSourceSpan` is a frozen half-open range between two locations
from the same source-unit identity. Existing Legacy token readers still return
`SourceString` values, now with one canonical `source_span`; the established
`source_file`, `source_line`, `source_cstart`, and `source_cend` accessors
delegate to that span. Compiler nodes, coverage metadata, module dumps, and
diagnostics therefore continue to consume the same token values and observable
coordinates.

The extracted scanner preserves the current Legacy accounting rather than
normalizing source:

- source content and its Ruby `String` encoding are retained unchanged;
  production file inputs come from `File.binread`, while standard input and
  direct callers retain the encoding supplied by their `String`;
- offsets index the retained Ruby `String`, so binary file input is byte-indexed
  while a non-binary direct string follows Ruby's character indexing; no
  universal byte-offset or Unicode display-column claim is made;
- ordinary scanner lines are one-based and columns are zero-based; LF advances
  the line, CR does not, CRLF advances once, and tabs and CR each consume one
  column without tab-stop expansion;
- for compatibility, the LF character itself belongs to the following line at
  column zero, as does the first character after it; token starts occur after
  whitespace, so Legacy token attribution remains unchanged;
- the cursor exposes the location at EOF, lookahead uses cloned scanner state,
  failed speculative parses retain the parent position, and an accepted parse
  commits only the child position through `merge!`;
- unterminated Legacy block, `#`, and `//` comments retain their existing
  `DabEndOfStreamError` boundary, and the compiler's established unknown-token
  and unexpected-EOF fallback diagnostics remain attributed to line and offset
  zero.

These rules characterize compatibility, not a redesigned text model. The
minimal-main and separator productions add no tab expansion, Unicode-width
policy, newline normalization, general Modern grammar, new bytecode, or runtime
behavior.

The dedicated Modern-source fixture format is active under
`test/modern_source/*.dabmtest`; its strict section schema and exact comparison
contract are documented in that directory. Its diagnostic corpus locks the
unsupported parser message, streams, portable filenames, entry boundary, and exact
bootstrap mismatch locations. The focused end-to-end RSpec contract owns the
minimal-main compiler, Ring, assembler, and VM behavior.
