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
| Production compiler frontend | One `DabSourceUnit` and `DabProgramStream` per input | An explicit `--syntax=PROFILE` applies to every unit. Otherwise, each unit independently infers Legacy from exact `.dab` or Modern from exact `.dabm`; standard input and unrecognized extensions derive the Legacy fallback. All units are validated before any is parsed. |
| Source formatter and format fixtures | One direct `DabProgramStream` | These practical single-source callers derive a Legacy source unit through the parser API compatibility default. |
| Assembler and decompiler assembly reader | `DabParser` | These consume assembly text through lower-level scanner helpers, not a Dab source-syntax profile. |
| Parser specifications and direct Ruby callers | `DabProgramStream` | Callers can pass `source_unit:` to preserve a complete input identity or `syntax_profile:` to derive one. Omitting both remains a narrow single-source Legacy compatibility path. Passing both is rejected rather than guessing precedence. |

The Modern identity, `.dabm` selection, and per-source-unit retention are
present, but Modern parsing is not. This change adds no second parser, grammar,
scanner/token rules, Modern fixtures, AST or IR behavior, bytecode, or runtime
changes. Those remain separate roadmap work.
