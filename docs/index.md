---
layout: home
title: Dab
---

Dab is an experimental, highly optimised dynamic language.

It is evolving from a small, evidence-led prototype toward a coherent,
general-purpose language. The current implementation, the Dab 0.1 acceptance
target, and the longer-term Dab 1.0 design are intentionally kept separate.

## Current 0.0.x prototype

Today, Dab is a very early prototype: a compiler and assembler written in Ruby
and a virtual machine written in C++. The checked-in implementation and tests
describe its actual behavior. It accepts trusted local source and artifacts
only; this site does not claim safe execution of hostile input.

## Planned Dab 0.1

Dab 0.1 is a planned acceptance target, not a statement of what the prototype
already implements. Development keeps the existing compiler, assembler,
bytecode format, VM, and tests, then evolves them in small verified steps.
Modern Ruby-esque source will use `.dabm` while `.dab` temporarily preserves
the legacy syntax; both will share the same semantic and runtime pipeline.

The release is anchored by one complete `wordfreq` command-line program. It
must compile without source changes and pass contracts for arguments, standard
streams, multiple files, strict UTF-8, Unicode word boundaries, collections,
sorting, errors, cleanup, and process status.

- [Read the planned Dab 0.1 contract](/dab-0.1.html)
- [Read the provisional `wordfreq` reference program](/wordfreq.html)

## Dab 1.0 design vision

The long-term intent is a productivity-first language that can support
low-level and high-level work without losing the readability of Ruby-esque
source code.

- **Everything is an object.** Unannotated values are dynamic; optional static
  types narrow the visible contract and catch provable errors earlier.
- **Mutability is explicit.** `let` and `var` describe binding reassignment,
  while mutable and read-only access are a separate dimension. Bang methods
  are guaranteed to be mutation-capable.
- **The object model stays legible.** Classes use nominal subtyping, one
  superclass, and protocols. Immutable classes make mutable and read-only
  references equivalent.
- **Programs become closed images.** Rings may transform the VM between build
  stages, but the application starts only after those stages are combined and
  optimized into one unified image.
- **Unsafe power is visible.** Native FFI and similar capabilities remain
  explicit rather than pretending to be safe or sandboxed.

That vision guides incremental work; it is not implementation proof.

- [Building the current prototype](/building.html)
- [Examples from the current repository](/examples.html)
