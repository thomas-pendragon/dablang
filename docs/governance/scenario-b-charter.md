# Scenario B charter: incremental modernization of Dab

**Status:** owner-selected direction; active from 2026-07-29<br>
**Scope:** governance and planning charter<br>
**Companion work log:** `Dab Scenario B Modernization` in the GitHub Wiki

## 1. Decision and objective

The owner has selected **Scenario B**: incrementally modernize the existing
Dab implementation toward a usable general-purpose language. This decision
overrides the audit's strategic recommendation for Scenario D; it does not
invalidate the audit's evidence, risks, or stop criteria.

The objective is to make measurable progress while preserving the existing
Ruby compiler, DAB bytecode format, C++ VM, tests, and Rings concept where
evidence shows they remain valuable. “Usable general-purpose language” is a
destination, not a present capability or an implementation mandate. Each stage
must prove a smaller, testable capability before new scope is admitted.

The authoritative baseline is the audit at
[`audit` / `DABLANG_AUDIT.md`](https://github.com/thomas-pendragon/dablang/blob/e3796a69c3ac1c0a2cf0c2ffc268a45cfc5acf9d/DABLANG_AUDIT.md), read as a
risk ledger. Its code and test observations must be re-verified before use in
an implementation decision.

## 2. Baseline as verified on 2026-07-29

These are dated observations, not promises for later commits.

| Type | Observation | Evidence |
| --- | --- | --- |
| Verified current fact | `master` is `5dc68e141c3f2274b3f38750b511ff6fffb9c8db`; merged maintenance includes PRs #9 and #10. | `git fetch origin master`; repository history |
| Verified current fact | The active `CI` workflow is PR-only and runs `PREMAKE='./premake5' bundle exec rake` on Ruby 3.3.12, 3.4.9, and 4.0.5. It does not explicitly run RSpec, examples, sanitizers, or fuzzing. | `.github/workflows/ruby.yml` |
| Verified current fact | In a disposable checkout of that SHA, `RBENV_VERSION=3.3.12 PREMAKE=/tmp/.../premake5 bundle exec rake` passed using Premake 5.0.0-beta8. The task can update tracked generated documentation, so it was not run in the change worktree. | local verification |
| Verified current fact | Standalone RSpec reported `70 examples, 1 failure, 16 pending`; the failure was `spec/compiler/readbin_spec.rb:155`. | local verification |
| Verified current fact | `master` was unprotected, and there were no open PRs or issues when checked. | GitHub API |
| Owner decision | Pursue Scenario B despite the audit's recommendation of Scenario D. | this charter |
| Planned work | Establish a trusted baseline, define implemented semantics, then harden and expand only behind gates. | sections 5–9 |

## 3. Users and use cases to validate

The following are assumptions, not personas or promises. A stage may validate,
refine, or reject them.

1. **Language learner/contributor:** can build the compiler and VM, change a
   bounded language behavior, and get a clear test result.
2. **Small-program author:** can compile and run a documented subset without
   relying on undocumented type, runtime, or platform behavior.
3. **Rings experimenter:** can use an explicitly experimental multi-stage
   workflow with stated artifact, invalidation, and trust semantics.
4. **Future library author:** can rely on a small stable core only after the
   compatibility policy and release contract exist.

Each proposed product feature must name one target user, a reproducible
workflow, and success evidence. A feature without a user and acceptance
criteria stays out of implementation.

## 4. Principles and non-goals

### Principles

- **Evidence before expansion.** Tests and implementation establish current
  semantics; documents become normative only through an accepted decision.
- **Small, gated increments.** One safety, semantics, or developer-experience
  boundary at a time; no broad cleanup disguised as modernization.
- **Compatibility is chosen, not assumed.** Preserve observed behavior by
  default and make breaking changes deliberate, versioned, and tested.
- **Security precedes reach.** A feature cannot claim safe handling of
  untrusted bytecode or code unless the relevant boundary is designed and
  verified.
- **Reproducibility is a capability.** Toolchain, generated artifacts, and
  Ring inputs are part of the contract whenever they affect behavior.
- **English is the repository language.** New or changed repository docs and
  Wiki work-log content are English.

### Explicit non-goals until a later charter amendment

- A full rewrite, a new compiler backend, LLVM/JIT adoption, or a replacement
  VM.
- New syntax, broad standard-library growth, package management, IDE work, or
  marketing claims about a general-purpose production language before the
  applicable gates pass.
- Compatibility with undocumented README intent merely because it is written
  down; this includes unimplemented `T?`, `T!`, inference, and Rings caching
  semantics.
- Execution of hostile bytecode, unreviewed Ring artifacts, or arbitrary FFI
  as a supported safe workflow.
- Changing repository settings, release management, or generated files as a
  side effect of charter work.

## 5. Decisions, semantics, and compatibility

### Decision records

An ADR or a clearly labeled section in this charter is required before a
change that affects syntax, typing, `nil`, dispatch, bytecode layout, loader
validation, Ring import/export, memory ownership, FFI, diagnostics, or a
documented compatibility promise. It must include:

- context and current observed behavior;
- decision and alternatives considered;
- compatibility classification: preserving, additive, breaking, or unknown;
- migration/rejection behavior and test corpus;
- owner, acceptance criteria, and reversal/stop condition.

### Unknown semantics

Unknown behavior is not permission to guess. Create a decision question with
an executable acceptance criterion. For example: “Does a regular typed slot
accept `nil` in the supported subset?” is resolved only by characterization
tests and an accepted compatibility decision, not by copying old prose.

### Compatibility policy

Before a published compatibility line exists, the test corpus and documented
implemented subset are the provisional compatibility surface. Breaking changes
need a focused PR, a decision record, a before/after fixture or artifact, and
an explicit version/migration decision. Undocumented behavior can be rejected
only after it is identified and reviewed; it is not silently redefined.

## 6. Safety and trust boundary

Until Stage 2 succeeds, Dab supports **trusted local source and artifacts
only**. This is a limitation, not a claim that trusted input is free of bugs.
The loader, binary format, pointer and string conversions, memory ownership,
and FFI are safety-sensitive areas. Work in these areas must define inputs,
validation, failure behavior, resource limits, and tests before expanding use.

Rings are experimental. No cache correctness, determinism, source provenance,
or IDE visibility claim is allowed until it is represented by tested artifact
metadata and a reproducibility gate. Raw FFI remains an explicit unsafe
capability; it must not become a transitive default of a normal program.

### Dab 0.0.18 String-to-IntPtr lifetime decision

**Status:** proposed<br>
**Owner:** Scenario B MASTER THREAD<br>
**Compatibility:** preserving safety repair

`LiteralString` and `DynamicString` values use the VM's reference-counted
object proxy. `IntPtr` values are otherwise raw, borrowed pointers with no
general release protocol. The `CLASS_STRING` to `CLASS_INTPTR` conversion
instead took `c_str()` from the temporary `std::string` returned by
`DabValue::string()`. The temporary was destroyed before the returned pointer
could be used, so the conversion had no valid lifetime.

For only that conversion, the VM copies the string bytes, including the
terminating null byte, into storage shared by all copies of the returned
`DabValue`. The pointer is valid until the last copy of that value is released,
destroyed, or assigned another value. Releasing the last copy frees the storage
exactly once. Copy assignment retains the incoming owner before releasing the
displaced value, while self-assignment is a no-op. The conversion supplies a
writable, null-terminated snapshot for a synchronous trusted-local FFI call.
Foreign code must not retain the pointer beyond the lifetime of an owning
`DabValue`; later source-string changes do not change the snapshot.

Borrowing from the source was rejected because source destruction or
reallocation would invalidate the pointer. `strdup` was rejected because it
would require a manual release protocol and repeat the separate
`DynamicString` leak. A general owning-pointer redesign would exceed this item.
Other `IntPtr` sources keep their prior borrowed behavior; this decision does
not change `DynamicString` or `ByteBuffer` to `IntPtr`, or pointer-to-string
conversions.

No bytecode, result class, diagnostics, or supported synchronous FFI call
changes. Acceptance requires a native temporary/copy/last-release regression,
focused Ruby contracts, both sanitizer gates, and every normal platform CI job.
Reassess if supported FFI needs to retain pointers asynchronously or if
`IntPtr` gains a general ownership protocol. Dab remains a trusted-local
prototype, and raw FFI remains explicitly unsafe.

### Dab 0.0.22 version 3 section-payload decision

**Status:** proposed<br>
**Owner:** Scenario B MASTER THREAD<br>
**Compatibility:** preserving safety repair

A version 3 artifact consists of its fixed header, complete section table, and
the exact number of payload bytes declared by `size_of_data`. Section positions
are absolute addresses: subtracting `header.offset` maps a validated position
to the corresponding byte in that artifact. The loader previously trusted
those values after validating only the header and table. In particular,
`section.pos < header.offset` wrapped the subtraction in `section_stream`, and
the VM accepted payload ranges outside `size_of_data`, mismatched declared
sizes, and overlapping sections.

Before publishing a validated header, appending any input, slicing a section,
or dispatching a payload consumer, the loader rejects arithmetic wrap in the
declared artifact or absolute payload range. The input size must equal
`size_of_header + size_of_data`. Every section's half-open range must fit in
the absolute payload range, and non-empty section ranges must not overlap.
Zero-length sections may sit anywhere in the payload including its end;
non-overlapping sections may contain gaps or appear in any table order. These
rules preserve the current version 3 layout and native-byte-order behavior.

Malformed artifacts use the existing deterministic VM boundary: stderr names
the failed bytecode-header condition and the VM exits with status 1. All inputs
validate before any is appended or changes VM section state. Acceptance
requires valid offset, gap, ordering, adjacency, and zero-length controls;
negative boundary, underflow, overflow, membership, overlap, and transactional
contracts; the compatibility and complete gates; and focused ASan and UBSan
proof. This decision does not validate opcode identity, String or symbol
content, FFI, Rings semantics, or hostile bytecode generally.

## 7. Ordered stages and gates

| Stage | Objective | Entry dependencies | Exit gate |
| --- | --- | --- | --- |
| 0. Governance and truth | Establish this charter, a work log, an implementation truth table, and a repeatable baseline. | Owner decision; audit risk ledger | Current behavior, known failures, toolchain, and supported scope have dated evidence. |
| 1. Reproducible developer loop | Make build/test results repeatable and classify every known failure. | Stage 0 truth table | A clean supported checkout has one documented full gate; RSpec status and generated-file effects are explicit. |
| 2. Runtime and artifact safety | Define and test bytecode, loader, ownership, error, and FFI trust boundaries. | Stage 1 characterization suite | Supported artifacts are validated within documented bounds; unsafe modes are explicit; focused safety evidence is green. |
| 3. Implemented language core | Specify and stabilize a small language subset, including types and `nil`, calls, classes, and diagnostics. | Stage 2 boundary; accepted semantic ADRs | The subset has normative docs, positive/negative tests, and a compatibility statement. |
| 4. Controlled usability | Add only user-backed modules, library APIs, Rings metadata, or tools needed by validated use cases. | Stage 3; one named user workflow per feature | A contributor can complete the named workflow reproducibly and maintain it with the documented gate. |
| 5. General-purpose reassessment | Decide whether evidence supports broader language investment. | Stages 0–4 evidence; external use evidence | Continue, narrow, or archive decision recorded with no open critical boundary debt. |

No stage completes because a PR merged. The MASTER THREAD records the exit
evidence in the Wiki TABELKA and verifies it at the current commit.

## 8. Initial controlled backlog

The Wiki is the persistent checkable TODO source. The following order is
binding until an owner-approved decision changes it:

1. Record a repeatable baseline (Ruby, Bundler, Premake, compiler, OS) and
   account for generated documentation changes from `rake`.
2. Define a truthful test matrix: default Rake tasks, standalone RSpec,
   examples, failures, pending tests, timeout behavior, and expected owners.
3. Write the first implemented-semantics truth table for types, `nil`, calls,
   classes, errors, and Rings. Each unknown has an acceptance test.
4. Classify and resolve or explicitly defer the active RSpec failure before
   claiming a complete Ruby-level test gate.
5. Specify DAB artifact versioning, byte order, limits, and malformed-input
   handling before loader/VM expansion.
6. Define memory ownership and FFI capability decisions before new runtime or
   interop features.
7. Add Rings manifest/provenance work only after safety and semantic gates;
   validate determinism and invalidation rather than assuming them.

## 9. Stop and reassessment criteria

Pause and reassess Scenario B when any condition below is true:

- a Stage 1 baseline cannot be reproduced across the declared supported
  environment after focused repair attempts;
- Stage 2 cannot establish a credible bounded artifact and FFI boundary;
- a proposed feature lacks an owner, user workflow, semantic decision, or
  acceptance tests;
- work repeatedly expands syntax or libraries before prerequisites close;
- compatibility debt, unclassified failures, or safety debt grows faster than
  completed gates;
- no independent contributor or user can reproduce the controlled workflow by
  the Stage 4 review.

The reassessment result must be one of: continue with a narrowed stage,
redirect to a smaller research/educational scope, or archive/preserve the
project. It must cite current evidence rather than the audit alone.

## 10. Coordination contract

The MASTER THREAD owns the sequence, resolves cross-cutting decisions, and
maintains the Wiki's TABELKA. A SUBWORK owns one bounded row, updates its
evidence, and reports completion or a precise blocker. A TABELKA row includes:
`ID`, stage/gate, outcome, scope, prerequisite, owner, status, links, required
validation, decision reference, and blocker.

SUBWORK cannot advance a stage, redefine compatibility, or widen the scope.
The MASTER THREAD must re-check the exact commit, review state, and evidence
before marking a row or gate complete. This keeps the work log persistent
without turning it into an unbounded feature list.
