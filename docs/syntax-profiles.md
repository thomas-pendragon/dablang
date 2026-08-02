---
layout: page
title: Syntax profiles
---

# Syntax profiles

The source parser has one explicit, finite syntax-profile model. A profile is a
`DabSyntaxProfile` value retained by each `DabProgramStream`; it is not mutable
process-global or environment state.

The registered identities are `DabSyntaxProfile::LEGACY` and
`DabSyntaxProfile::MODERN`. Modern grammar is not implemented: selecting the
Modern identity fails before parsing rather than sending Modern source through
the legacy parser. Omitting the `syntax_profile:` keyword when constructing a
program stream or compiler frontend still selects the canonical legacy value,
so existing legacy source, diagnostics, and compiler output remain unchanged.
An explicit compiler API invocation can pass the legacy profile without adding
a command-line option:

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
`DabSyntaxProfile.fetch`, and passes the resulting canonical profile to the
compiler frontend. Omitting the option remains byte-for-byte compatible with
the legacy default.

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

The compiler continues to resolve one profile for the whole invocation.
Multiple `.dab` inputs select Legacy and multiple `.dabm` inputs select Modern.
Without an explicit option, mixing inferred `.dab` and `.dabm` profiles exits
with status 2 and `compiler: input filenames select multiple Dab syntax
profiles: legacy, modern; use --syntax=PROFILE to select one explicitly`.
This deterministic rejection avoids per-source-unit profile selection.

## Current construction paths

| Consumer | Parser construction | Current profile contract |
| --- | --- | --- |
| Production compiler frontend | One `DabProgramStream` per input | The compiler CLI gives an explicit `--syntax=PROFILE` option precedence, otherwise infers Legacy from exact `.dab` or Modern from exact `.dabm`, rejects mixed inferred identities, and passes one validated invocation-level profile to every stream. Standard input and unrecognized extensions retain the legacy fallback. |
| Source formatter and format fixtures | `DabProgramStream` | The parser API default selects legacy. |
| Assembler and decompiler assembly reader | `DabParser` | These consume assembly text through lower-level scanner helpers, not a Dab source-syntax profile. |
| Parser specifications and direct Ruby callers | `DabProgramStream` | Callers may omit the profile for legacy compatibility or pass `DabSyntaxProfile::LEGACY` explicitly. |

The Modern identity and `.dabm` selection are present, but Modern parsing is
not. This change adds no per-source-unit selection, second parser, grammar,
scanner/token rules, AST or IR behavior, fixtures, bytecode, or runtime changes.
Those remain separate roadmap work.
