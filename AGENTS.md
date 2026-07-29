# Dab contributor guide

## Project boundary

Dab is an early prototype with a Ruby compiler and assembler, a DAB bytecode
format, and a C++ virtual machine. Treat the checked-in implementation and its
tests as the source of truth for current behavior. Design documents, the README,
and historical TODO items describe intent; they are not proof that a feature is
implemented.

The project is being modernized incrementally under the Scenario B charter in
[`docs/governance/scenario-b-charter.md`](docs/governance/scenario-b-charter.md).
That is an owner decision, not an assertion that the audit recommended this
path. Preserve the distinction in code, documentation, reviews, and planning.

## Repository map

| Area | Purpose | Change discipline |
| --- | --- | --- |
| `src/compiler/`, `src/shared/`, `src/tobinary/` | Ruby parser, AST/IR passes, compiler, and assembler | Semantic changes require an executable contract and compatibility decision. |
| `src/cvm/`, `src/cshared/`, `src/cdisasm/` | VM, bytecode loading, values, FFI, shared binary structures, and disassembler | Safety-sensitive native code; do not accept untrusted artifacts without an explicit trust-boundary decision. |
| `src/frontend/`, `tasks/`, `Rakefile` | CLI orchestration, test frontends, and generated artifacts | Keep task names and generated-file ownership clear. |
| `test/`, `spec/` | End-to-end fixtures and Ruby RSpec contracts | Add characterization and negative tests before changing observable behavior. |
| `stdlib/`, `examples/` | Dab library and demonstrations | Do not use an example as a safety or compatibility guarantee. |
| `docs/` | Tracked design and governance documentation | English only. Do not hand-edit generated class/opcode documentation. |

## Safety and trust boundaries

- Treat `.dabcb` input, Rings, bytecode loaders, serialization, pointer/string
  conversions, memory ownership, and FFI as safety-sensitive.
- Today, the runtime must be described as suitable only for trusted local input
  unless an approved change establishes and tests a narrower or stronger
  boundary. Never imply a sandbox or safe execution of hostile bytecode.
- FFI is an explicit unsafe capability. Do not broaden it, add a new native
  entry point, or relax validation as incidental cleanup.
- A parser, loader, VM, or ownership fix must state malformed-input behavior,
  bounds/overflow behavior where applicable, and its test evidence.

## Semantic and compatibility discipline

- Preserve current observable behavior by default. If behavior is unknown,
  record a decision question and acceptance criteria; do not infer semantics
  from aspirational text such as `Type?`, `Type!`, general type inference, or
  Rings cache claims.
- Every intentional semantic change needs a decision record in the Scenario B
  charter or a linked ADR before implementation. It must name the prior
  behavior, target behavior, compatibility impact, migration or rejection
  policy, and tests.
- Prefer characterization tests, golden artifacts, and negative tests to broad
  refactors. Keep source, bytecode, and VM changes separable where possible.
- Do not start syntax expansion, a package manager, a new backend, a full
  rewrite, or general-purpose-language marketing before the charter gates allow
  it.

## Build and test guidance

- Read `Rakefile` before assuming a task name. `rake spec` is an alias for the
  Dab fixture task, not the Ruby RSpec suite.
- The default `bundle exec rake` generates tracked documentation with `Last
  revised` dates. Run it in a disposable worktree, inspect resulting changes,
  and never commit generated churn unless the task specifically requires it.
- The active PR workflow downloads Premake 5.0.0-beta8 and runs `bundle exec
  rake` on Ruby 3.3.12, 3.4.9, and 4.0.5. Follow the current workflow rather
  than old build instructions when reproducing CI.
- Run the smallest relevant task first, then the required gate. For semantic
  work, run affected fixture tests and `bundle exec rspec`; for native boundary
  work, add the appropriate malformed-input or sanitizer proof.
- Always run `git diff --check`. Documentation-only changes require Markdown
  link and structure review; they do not justify changing generated files.

## Documentation and pull requests

- All new or modified repository documentation, comments intended for
  contributors, Wiki pages, issues, and PR descriptions must be in English.
- Keep documentation accurate about maturity: “prototype” and “experimental”
  are facts of the current project position; do not promise unimplemented type
  semantics, deterministic Rings, portability, safety, or performance.
- Keep PRs small and single-purpose. State the exact base SHA, behavioral or
  governance decision, test evidence, generated-file status, and any known
  limitations. Do not merge your own work unless explicitly authorized.
- Repository settings are out of scope for ordinary changes. As of the live
  baseline on 2026-07-29, `master` was unprotected; report governance gaps but
  do not alter settings without explicit authorization.

## MASTER THREAD, SUBWORK, and TABELKA

One MASTER THREAD owns the Scenario B sequence, cross-cutting decisions, and
the canonical planning view. A SUBWORK has one bounded deliverable, one branch
or no branch for read-only work, and no authority to broaden the charter.

Before starting a SUBWORK, the MASTER THREAD records it in the **TABELKA**
(the compact coordination table in the Scenario B Wiki work log) with: ID,
stage/gate, objective, repository area, prerequisite decision/evidence,
owner, status, branch/PR or issue link, validation required, and blocker.

SUBWORK rules:

1. Read this file and the charter, then claim exactly one TABELKA row.
2. Preserve unknown semantics as a decision request with acceptance criteria.
3. Report the exact base and head SHA, changed paths, evidence, test state,
   risks, and blocker back to the MASTER THREAD; update only the claimed row.
4. Do not create parallel work that overlaps a claimed row, silently reopen a
   completed gate, or mark a gate complete without its checkable evidence.
5. The MASTER THREAD alone advances a stage, accepts a compatibility decision,
   and moves the persistent Wiki work log forward after verifying evidence.

TABELKA is coordination metadata, not a replacement for tests, decision
records, review, or the GitHub Wiki work log.
