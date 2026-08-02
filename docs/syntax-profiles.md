---
layout: page
title: Syntax profiles
---

# Syntax profiles

The source parser has one explicit, finite syntax-profile model. A profile is a
`DabSyntaxProfile` value retained by each `DabProgramStream`; it is not mutable
process-global state, environment state, or a value inferred from a filename.

The only registered profile is `DabSyntaxProfile::LEGACY`. Omitting the
`syntax_profile:` keyword when constructing a program stream or compiler
frontend selects that same canonical value, so existing legacy source,
diagnostics, and compiler output remain unchanged. An explicit compiler API
invocation can pass the profile without adding a command-line option:

```ruby
run_dab_compiler(settings, context,
                 syntax_profile: DabSyntaxProfile::LEGACY)
```

`DabSyntaxProfile.fetch('legacy')` returns the canonical frozen identity.
Unknown names raise `DabSyntaxProfileError`, and parser or frontend construction
rejects strings, symbols, booleans, `nil`, and other unregistered values rather
than guessing or falling back.

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
specified at most once`. Empty and unknown values, including
`--syntax=` and `--syntax=modern`, exit with status 2 using the canonical
unknown-profile diagnostic. No modern profile is registered.

## Current construction paths

| Consumer | Parser construction | Current profile contract |
| --- | --- | --- |
| Production compiler frontend | One `DabProgramStream` per input | The compiler CLI resolves at most one `--syntax=PROFILE` option to one validated invocation-level profile passed explicitly to every stream; the default is legacy. |
| Source formatter and format fixtures | `DabProgramStream` | The parser API default selects legacy. |
| Assembler and decompiler assembly reader | `DabParser` | These consume assembly text through lower-level scanner helpers, not a Dab source-syntax profile. |
| Parser specifications and direct Ruby callers | `DabProgramStream` | Callers may omit the profile for legacy compatibility or pass `DabSyntaxProfile::LEGACY` explicitly. |

There is no selectable Modern Dab profile yet. In particular, this model adds
no `.dab` or `.dabm` inference, per-source-unit selection, second parser,
grammar, token, or diagnostic behavior. Those remain separate roadmap work.
