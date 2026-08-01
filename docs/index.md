---
layout: home
title: Dab
---

Dab is an experimental language project with a long-term design vision and a
small, evidence-led prototype. The three states below are intentionally kept
separate.

## Current 0.0.x prototype

Today, Dab is a very early prototype: a compiler and assembler written in Ruby
and a virtual machine written in C++. The checked-in implementation and tests
describe its actual behavior. It accepts trusted local source and artifacts
only; this site does not claim safe execution of hostile input.

## Planned Dab 0.1

Dab 0.1 is a planned acceptance target, not a statement of what the prototype
already implements. It is anchored by a complete `wordfreq` command-line
program and its acceptance gates.

- [Read the planned Dab 0.1 contract](/dab-0.1.html)
- [Read the provisional `wordfreq` reference program](/wordfreq.html)

## Dab 1.0 design vision

The long-term intent is a productivity-first, Ruby-esque language that can
support low-level and high-level work through explicit semantics, a coherent
object and type model, staged program construction, and a focused standard
library. That vision guides incremental work; it is not implementation proof.

- [Building the current prototype](/building.html)
- [Examples from the current repository](/examples.html)
