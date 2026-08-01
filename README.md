# Dab programming language

[![CI](https://github.com/thomas-pendragon/dablang/actions/workflows/ruby.yml/badge.svg?branch=master)](https://github.com/thomas-pendragon/dablang/actions/workflows/ruby.yml)

Dab is an experimental language project. Its long-term **Dab 1.0 design
vision** is a coherent, productivity-first language that can span low-level
systems work and higher-level applications, while keeping language semantics,
tooling, and runtime boundaries explicit.

## Current 0.0.x prototype

The current prototype is not that design vision. It currently contains a Ruby
compiler and assembler, a C++ virtual machine, and the implementation and test
surfaces in this repository. The prototype accepts trusted local source and
artifacts only; it is not a sandbox or a safe host for untrusted bytecode.

The repository's source and tests are the only evidence for implemented
behavior. This README describes intent and must not be read as implementation
proof.

## Planned Dab 0.1

Dab 0.1 is a planned, executable acceptance target, not a shipped language
claim. Its finish line is the provisional `wordfreq` program compiling without
source changes and passing its complete acceptance contract. Read the
[planned Dab 0.1 acceptance contract](docs/dab-0.1.md) and the
[canonical provisional `wordfreq` reference program](docs/wordfreq.md) for
the bounded target and its explicit open gates.

## Dab 1.0 design vision

The long-term intent is a Ruby-esque language with a clear type and object
model, deliberate compatibility choices, staged program construction, and a
small standard-library foundation. These are design decisions to implement and
verify incrementally; they do not describe the current prototype as complete.
The Scenario B charter records the governing evidence and stop conditions.

## Explore

- [Public site](https://dablang.net/)
- [Building the current prototype](docs/building.md)
- [Dab 0.1 acceptance contract](docs/dab-0.1.md)
- [Provisional `wordfreq` reference program](docs/wordfreq.md)

MIT license.
