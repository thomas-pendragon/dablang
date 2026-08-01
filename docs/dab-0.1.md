---
layout: page
title: Planned Dab 0.1 acceptance contract
---

# Planned Dab 0.1 acceptance contract

**Status:** planned evolution target; not implemented or released.

This page is a concise public guide to the planned Dab 0.1 finish line. It is
design content derived from the accepted Scenario B Wiki decisions; it does
not establish present compiler, VM, standard-library, Rings, or safety
behavior.

## The acceptance target

Dab 0.1 is planned to accept one complete source program without source
changes: the [provisional `wordfreq` bare CLI](/wordfreq.html). The target is
met only when that program compiles and passes its complete behavioral
acceptance contract. A page, example, or planned API is not evidence that the
current prototype implements it.

The program is deliberately substantial: it exercises command-line parsing,
standard input and files, strict UTF-8 processing, Unicode word boundaries,
collections and sorting, errors, resource cleanup, standard streams, and
process status. Its source remains provisional until the relevant language and
standard-library contracts have passed their gates.

## Planned evolution, not present behavior

The planned transition keeps the existing implementation as an incremental
starting point. Through the target, `.dabm` is intended to select the canonical
modern Ruby-esque syntax while `.dab` continues to select the legacy syntax;
both are intended to share one semantic pipeline, bytecode format, VM, and
standard-library image. This is a plan, not a feature currently claimed by
this site.

The target does not imply that all longer-term design decisions are required
or implemented. It excludes, among other future work, a new backend, a full
rewrite, general-purpose production claims, unrestricted unsafe execution, and
unaccepted API semantics.

## Canonical design inputs

The English GitHub Wiki remains the detailed design source:

- [Dab 0.1 Language Design Decisions](https://github.com/thomas-pendragon/dablang/wiki/Dab-0.1-Language-Design-Decisions)
- [Dab 0.1 Evolution Plan](https://github.com/thomas-pendragon/dablang/wiki/Dab-0.1-Evolution-Plan)
- [Dab 0.1 Standard Library and Acceptance Programs](https://github.com/thomas-pendragon/dablang/wiki/Dab-0.1-Standard-Library-and-Acceptance-Programs)
- [Wordfreq Bare CLI Provisional](https://github.com/thomas-pendragon/dablang/wiki/Wordfreq-Bare-CLI-Provisional)

For the implementation truth, use the repository source and tests. For the
longer horizon, see the [Dab 1.0 design vision](/). The Scenario B charter
governs the evidence, compatibility, safety, and stop conditions for making
this plan real.
