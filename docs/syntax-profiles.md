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
`DabSyntaxProfile::MODERN`. Modern grammar is not implemented: selecting the
Modern identity fails before parsing rather than sending Modern source through
the legacy parser. Direct callers can provide a complete source unit:

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
`DabUnsupportedSyntaxProfileError` before consuming source.

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
diagnostic. `--syntax=modern` resolves the canonical identity, then exits with
status 2 and `compiler: unsupported Dab syntax profile "modern": parser is not
implemented`.

When no syntax option is explicit, exact lowercase `.dab` selects
`DabSyntaxProfile::LEGACY` and exact lowercase `.dabm` selects
`DabSyntaxProfile::MODERN`. Modern selection then produces the stable
unsupported-parser diagnostic above; it does not claim compilation. An
explicit option takes precedence over filename inference, so
`--syntax=legacy FILE.dabm` intentionally remains a forced legacy parse.
Standard input, uppercase `.DAB` or `.DABM`, and other unrecognized filename
extensions retain the existing canonical legacy fallback.

Without an explicit option, each source unit selects its profile independently.
Mixing `.dab` and `.dabm` therefore no longer fails merely because the profiles
differ: the `.dab` unit retains Legacy and the `.dabm` unit retains Modern,
regardless of input order. Before the frontend opens or parses any source (and
before it loads Ring bases), it validates parser support for the complete source
unit list. A mixed invocation therefore fails transactionally with status 2 and
the stable unsupported-Modern diagnostic. No Legacy input is partially parsed
or compiled first. With `--syntax=legacy` or `--syntax=modern`, the selected
canonical identity is instead assigned to every source unit before the same
validation.

## Current construction paths

| Consumer | Parser construction | Current profile contract |
| --- | --- | --- |
| Production compiler frontend | One `DabSourceUnit`, shared `DabScanner` foundation, and `DabProgramStream` per input | An explicit `--syntax=PROFILE` applies to every unit. Otherwise, each unit independently infers Legacy from exact `.dab` or Modern from exact `.dabm`; standard input and unrecognized extensions derive the Legacy fallback. All units are validated before any is parsed. |
| Source formatter and format fixtures | One direct `DabProgramStream` | These practical single-source callers derive a Legacy source unit through the parser API compatibility default. |
| Assembler and decompiler assembly reader | `DabParser` | These consume assembly text through lower-level scanner helpers, not a Dab source-syntax profile. |
| Parser specifications and direct Ruby callers | `DabProgramStream` | Callers can pass `source_unit:` to preserve a complete input identity or `syntax_profile:` to derive one. Omitting both remains a narrow single-source Legacy compatibility path. Passing both is rejected rather than guessing precedence. |

## Shared scanner and source locations

`DabScanner` is the syntax-neutral cursor and location boundary below the
existing `DabParser`. The production Legacy `DabProgramStream` uses that
scanner through inheritance; the scanner is not an unused Modern-only API.
Every scanner receives one frozen `DabSourceUnit`, and every location and span
retains that exact source-unit object and therefore its filename and canonical
syntax profile. A scanner may carry a Modern source unit so a future parser can
reuse this boundary, but `DabProgramStream` still rejects Modern before any
Legacy token rule runs.

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
- unterminated block, `#`, and `//` comments retain their existing
  `DabEndOfStreamError` boundary, and the compiler's established unknown-token
  and unexpected-EOF fallback diagnostics remain attributed to line and offset
  zero.

These rules characterize compatibility, not a redesigned text model. This
foundation adds no tab expansion, Unicode-width policy, newline normalization,
Modern token definitions, grammar, source fixtures, AST/IR behavior, bytecode,
or runtime behavior.

The Modern identity, `.dabm` selection, and per-source-unit retention are
present, but Modern parsing is not. Those remain separate roadmap work.
