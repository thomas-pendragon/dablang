# Dab contributor guide

## Project boundary

Dab is an early prototype with a Ruby compiler and assembler, a DAB bytecode
format, and a C++ virtual machine. Treat the checked-in implementation and its
tests as the source of truth for current behavior. Design documents, the README,
and historical TODO items describe intent; they are not proof that a feature is
implemented.

The project is being modernized incrementally under the Scenario B charter and
work log in the [English GitHub Wiki](https://github.com/thomas-pendragon/dablang/wiki/Scenario-B-Modernization).
That is an owner decision, not an assertion that the audit recommended this
path. Preserve the distinction in code, documentation, reviews, and planning.

## Roadmap and version bookkeeping

- Treat every `Original #` in the evolution plan as immutable and render it as
  a bare integer, separate from the version. Inserted maintenance work uses `—`
  in that column; never renumber later original items to make room.
- Advance the root `VERSION` sequentially in merge order, even when roadmap
  items are implemented out of original-number order. Rebase a ready branch on
  the current exact `master`, then assign the next unmerged version before the
  final validation cycle.
- `VERSION` is the sole current-version authority. Tools must read or receive
  it through the build; tests may validate its format or derive expected output
  from it, but must not pin the current release literal.
- Fill the evolution plan's date and PR columns only after the change is
  merged. Render pull-request links as `[#NN]`, never `PR #NN`.

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
- Every intentional semantic change needs a decision record in the canonical
  Scenario B Wiki or a linked ADR before implementation. It must name the prior
  behavior, target behavior, compatibility impact, migration or rejection
  policy, and tests.
- Prefer characterization tests, golden artifacts, and negative tests to broad
  refactors. Keep source, bytecode, and VM changes separable where possible.
- Extend Modern syntax one roadmap row at a time. Preserve every previously
  accepted source's assembly/runtime behavior and every intentionally rejected
  near miss unless the current row explicitly changes it; do not generalize a
  bootstrap parser into adjacent literals, operators, statements, or types.
- Do not start syntax expansion, a package manager, a new backend, a full
  rewrite, or general-purpose-language marketing before the charter gates allow
  it.

## Work isolation and live-state checks

- For mutable work, confirm GitHub authentication, fetch the intended base,
  and verify both its exact SHA and root `VERSION` before editing. Stop and
  report drift instead of silently selecting a newer base.
- Use one clean isolated worktree and one `tomasz/` branch per SUBWORK. Never
  modify the shared launch checkout, another agent's worktree, or an unrelated
  dirty branch.
- Use the `ship-feature-pr` workflow for implementation PRs and the GitHub
  workflow for live PR state when those skills are available. Local confidence
  never replaces exact-head GitHub evidence.
- Before any approved squash merge, re-read the PR head, required checks,
  mergeability, review state, and unresolved threads. Use a head-match guard
  when the merge tool supports it, then verify the resulting `master` SHA and
  root `VERSION`.

## Build and test guidance

- Read `Rakefile` before assuming a task name. `rake spec` runs the Ruby RSpec
  suite; `rake dab_fixture_spec` runs the inherited Dab fixture suite.
- The default `bundle exec rake` owns `docs/vm/opcodes.md`, `docs/classes.md`,
  and `docs/classes/*.md`. They do not embed checkout time or revision metadata.
  The complete gate rejects pre-existing edits and reports any
  generated-documentation churn, so a clean checkout with current outputs can
  run it in place.
- The active PR workflow downloads Premake 5.0.0-beta8 and runs `bundle exec
  rake` through `ruby script/complete_gate.rb` on Ruby 3.3.12, 3.4.9, and
  4.0.5. Follow the current workflow rather than old build instructions when
  reproducing CI.
- Run the smallest relevant task first, then the required gate. For semantic
  work, run affected fixture tests and `bundle exec rspec`; for native boundary
  work, add the appropriate malformed-input or sanitizer proof.
- Use `ruby script/toolchain_preflight.rb` for the fast read-only environment
  check. Use `ruby script/complete_gate.rb` as the authoritative normal gate;
  prefer a disposable exact-head checkout when preserving a feature worktree's
  generated-file state matters.
- A fresh worktree may not contain `bin/cvm`, `bin/cdisasm`, or `bin/cdumpcov`.
  In that state, a broad bare RSpec failure is not authoritative: run focused
  Ruby contracts first and let the complete gate build native tools before the
  full suite.
- Always run `git diff --check`. Documentation-only changes require Markdown
  link and structure review; they do not justify changing generated files.
- Fixture and VM test output is concise by default. Use `DAB_TEST_VERBOSE=1`
  when detailed successful-test compiler, assembler, VM, and diagnostic output
  is needed; failures replay the captured per-test details automatically.
- Keep binary pipes and byte fixtures in binary mode on Windows; Ruby text mode
  can translate byte `0x0a` and corrupt artifacts. Use narrowly scoped
  `.gitattributes` LF rules for canonical source fixtures rather than changing
  line-ending policy globally.

## Documentation and pull requests

- All new or modified repository documentation, comments intended for
  contributors, Wiki pages, issues, and PR descriptions must be in English.
- Keep documentation accurate about maturity: “prototype” and “experimental”
  are facts of the current project position; do not promise unimplemented type
  semantics, deterministic Rings, portability, safety, or performance.
- Keep PRs small and single-purpose. State the exact base SHA, behavioral or
  governance decision, test evidence, generated-file status, and any known
  limitations. Do not merge your own work unless explicitly authorized.
- Public-site publication is controlled by `docs/_data/public_site.yml` and
  validated with
  `BUNDLE_GEMFILE=docs/Gemfile bundle exec ruby script/public_site.rb`. Do not
  publish governance, CI, sanitizer, toolchain, or test-harness pages merely
  because they live under `docs/`.
- Keep the public README and `dablang.net` pages self-contained; visitors must
  not need the internal Wiki for the project's central product story, and
  internal labels such as “Scenario B” must not appear as public product
  language. Use the product-design workflow and rendered browser evidence for
  visual site work. Bind local preview servers to `0.0.0.0` and report the LAN
  URL when review happens from another machine.
- Repository settings are out of scope for ordinary changes. Verify live
  governance state when it matters, report gaps, and do not alter settings
  without explicit authorization.

### PR finish line

A PR is ready only when all of the following are true on the same exact head:

1. The PR is ready/non-draft, correctly labeled, conflict-free, and reports
   `MERGEABLE` / `CLEAN`.
2. Every job required by the current workflow is green, including supported
   Linux Ruby, macOS, Windows, public-site, ASan, and UBSan coverage where the
   workflow defines them.
3. Copilot has reviewed the current head and every changed file. Inspect both
   visible comments and the review body for suppressed findings; a review on a
   stale commit does not count.
4. GraphQL review-thread readback shows zero unresolved threads, no actionable
   top-level or inline comment remains, no review request is pending, and the
   feature worktree is clean.

Request a fresh review with `gh pr edit <number> --add-reviewer @copilot` when
needed and compare the submitted review's commit OID with the live head. If
service delay, dependency order, unrelated CI failure, or an unresolved finding
blocks the finish line, report `review-blocked`, `dependency-blocked`, or
`CI-blocked` precisely instead of calling the work done.

## MASTER THREAD, SUBWORK, and TABELKA

One MASTER THREAD owns the Scenario B sequence, cross-cutting decisions, and
the canonical planning view. A SUBWORK has one bounded deliverable, one branch
or no branch for read-only work, and no authority to broaden the charter.

Before starting a SUBWORK, the MASTER THREAD records it in the **TABELKA**
(the compact coordination table in the Scenario B Wiki work log) with: ID,
stage/gate, objective, repository area, prerequisite decision/evidence,
owner, status, branch/PR or issue link, validation required, and blocker.

SUBWORK rules:

1. Read this file and the canonical English Wiki pages read-only, then claim
   exactly one TABELKA row.
2. Preserve unknown semantics as a decision request with acceptance criteria.
3. Report the exact base and head SHA, changed paths, evidence, test state,
   risks, and blocker back to the MASTER THREAD. Do not edit the Wiki/TABELKA.
4. Do not create parallel work that overlaps a claimed row, silently reopen a
   completed gate, or mark a gate complete without its checkable evidence.
5. Send a concise START/CLAIM callback immediately after verifying the base,
   worktree, branch, and scope. Send the structured completion or blocker
   callback without waiting for the user to ask for status.
6. Do not merge, edit repository settings, create releases/tags, or expand into
   a later roadmap row unless the owner explicitly authorizes that action.
7. The MASTER THREAD alone advances a stage, accepts a compatibility decision,
   and moves the persistent Wiki work log forward after verifying evidence.

TABELKA is coordination metadata, not a replacement for tests, decision
records, review, or the GitHub Wiki work log.
