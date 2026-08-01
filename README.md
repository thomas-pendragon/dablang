# Dab programming language

[![CI](https://github.com/thomas-pendragon/dablang/actions/workflows/ruby.yml/badge.svg?branch=master)](https://github.com/thomas-pendragon/dablang/actions/workflows/ruby.yml)

Dab is an experimental, highly optimised dynamic language.

The long-term **Dab 1.0 design vision** is a coherent, productivity-first
language that can span low-level systems work and higher-level applications,
while keeping language semantics, tooling, and runtime boundaries explicit.

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
source changes and passing its complete acceptance contract. The existing
compiler, assembler, bytecode format, VM, and tests remain the starting point;
`.dabm` will introduce the modern Ruby-esque syntax while `.dab` temporarily
retains the legacy syntax. Both feed the same semantic and runtime pipeline.

The target program exercises command-line arguments and streams, files,
strict UTF-8, Unicode word boundaries, collections, sorting, errors, resource
cleanup, and process status. The [Dab 0.1 acceptance contract](docs/dab-0.1.md)
and [provisional `wordfreq` program](docs/wordfreq.md) contain the complete
public specification.

## Dab 1.0 design vision

The long-term design has a Ruby-esque default syntax and a small set of explicit
semantic foundations:

- everything is an object;
- unannotated values remain dynamic, while optional static types can narrow the
  available operations and catch errors earlier;
- `let` and `var` control binding reassignment independently from mutable and
  read-only object access;
- classes use nominal subtyping with one superclass and protocols;
- immutable classes make mutable and read-only references equivalent;
- Rings construct one closed VM image before application execution begins;
- unsafe capabilities such as native FFI remain explicit.

These are design decisions to implement and verify incrementally; they do not
describe the current prototype as complete.

## Explore

- [Public site](https://dablang.net/)
- [Building the current prototype](docs/building.md)
- [Dab 0.1 acceptance contract](docs/dab-0.1.md)
- [Provisional `wordfreq` reference program](docs/wordfreq.md)

MIT license.
