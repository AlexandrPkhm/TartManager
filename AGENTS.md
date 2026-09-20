# AGENTS.md

Guidance for LLM agents (and humans) working in this repository. Read this
before writing or modifying code.

## Project overview

Tart Manager is a native macOS app (SwiftUI, macOS 14+) that provides a
Parallels-style control center for the [`tart`](https://github.com/cirruslabs/tart)
CLI: list VMs, run/stop/suspend, edit resources, create VMs from OCI images or
IPSW restores, and manage snapshots. It wraps the locally installed `tart`
binary — it does not implement virtualization itself.

The package has two targets with a strict separation:

- **`TartKit`** (library, `Sources/TartKit/`) — every line of tart CLI
  interaction, parsing, policy, and orchestration. The only place subprocesses
  are spawned.
- **`TartManager`** (executable, `Sources/TartManager/`) — a thin SwiftUI
  shell: views and an `AppModel` that delegate all decisions to tested
  `TartKit` units.

User-facing documentation lives in `README.md`; developer setup lives in
`DEVELOPMENT.md`.

## Toolchain

- **Swift 6.x toolchain** (`// swift-tools-version:6.0`), compiling in
  **Swift 5 language mode** (`swiftLanguageModes: [.v5]`). New code must keep
  compiling in Swift 5 mode (see the constraints below).
- **macOS 14.0+** deployment target (`platforms: [.macOS(.v14)]`); macOS 14+
  SwiftUI APIs are in use.
- **No external package dependencies** — `swift build`/`swift test` need no
  network resolution.
- Swift Package Manager only; there is no `.xcodeproj` (open `Package.swift`
  in Xcode).

## Commands

Always verify your work before reporting it done:

```sh
swift build
swift test --no-parallel
```

- **`swift test --no-parallel` is the mandatory deterministic mode.** Parallel
  `swift test` flakes on cancellation-timing races (wall-clock-dependent
  tests in `StreamingProcessTests`, `TartClientExportTests`,
  `TartClientCreateIPSWTests`, `TartClientPruneTests`, `JobManagerTests`,
  `CloneJobOutcomeTests`, `AppModelTests`). Do not report such flakes as
  product bugs; rerun serially.
- Filtering: `swift test --no-parallel --filter <SuiteName>` or
  `--filter "<SuiteName>.<testFunction>"`.
- `swift run` builds and launches the GUI app.

## Repository layout

```text
Sources/
  TartKit/      Library: TartClient + process runners, inventory, jobs,
                coordinators, policies, settings, logging
  TartManager/  Executable: SwiftUI app, sheets, settings, AppModel glue
Tests/
  TartKitTests/      Swift Testing suites mirroring TartKit types
    TestSupport/     StubBinary (fake tart scripts)
    Fixtures/        Real captured tart stderr for analyzer tests
  TartManagerTests/  AppModelTests (@MainActor)
.github/workflows/ci.yml   CI: swift test on macos-latest
.sdd/               Gitignored spec trail (PRD + per-issue docs)
```

## Architecture rules (do not violate)

1. **All tart CLI interaction goes through `TartClient`** in TartKit. The app
   target never spawns a process itself.
2. **One error-normalization choke point.** Subprocess failures map to
   `TartClientError`; `TartErrorAnalyzer` normalizes them into
   `TartOperationError` (message, 64 KiB-capped raw details, hint), presented
   via `AppModel.present(_:)` → `ErrorReportSheet`. Pre-spawn preconditions
   throw `TartClientError.commandFailed(..., exitCode: -1)` so they flow
   through the same surface. Unknown thrown errors are wrapped as
   `commandFailed(command: <operation-label>, exitCode: -1, ...)`.
3. **No silent no-ops.** Every gate refusal, race reconciliation, and degrade
   decision is logged and/or presented. Destructive operations
   (`TypedConfirmationGate`, `RestoreGate`, `ReplaceDiskGuard`, `CloneGuard`)
   are re-verified at the model boundary.
4. **`TART_HOME` is injected** into every storage-touching tart invocation via
   `TartCommandEnvironment`. Never rely on inherited shell environment.
5. **App target is thin plumbing.** Policies, validation, reconciliation, and
   job bodies live as pure, tested `TartKit` types; `AppModel` wires them to
   UI.

## Code style

- **Files and types.** One dominant type per file; file named after it.
  Immutable models are `struct`s conforming to `Equatable, Sendable` (plus
  `Identifiable`, `Hashable`, `Codable` as needed). Stateless helpers are
  caseless `enum`s with static functions. Stateful services/coordinators are
  `final class`es — `@MainActor` when UI-facing; lock-protected helpers are
  `@unchecked Sendable` guarded by `NSLock`.
- **Public surface.** Mark `public` only what the other target needs.
- **Swift 5 mode constraints.** Bare regex literals are not enabled — use
  extended literals (`#/…/#`). Long interpolated `Logger` calls can exceed
  the Swift 5 mode type checker's budget — assemble the string first, then
  log it (existing code documents this in comments).
- **Concurrency.** async/await throughout. `@MainActor` on `AppModel`,
  `InventoryService`, `JobManager`, and all coordinators. Blocking subprocess
  calls run in `Task.detached(priority: .userInitiated)` (user actions) or
  `.utility` (polling/refresh). Synchronous pre-checks happen before any
  `await` to close double-click races.
- **Error handling.** See rule 2. Never surface a raw process error; always
  normalize first.
- **Logging.** Use the `Logger` extensions in `Sources/TartKit/Logging.swift`
  — subsystem `app.TartManager` with the existing categories (`storage`,
  `settings`, `stop`, `suspend`, `errorReporting`, `TartClient`, `resources`,
  `clone`, `importJob`, `importCleanup`, `overcommit`, `snapshot`, `restore`,
  `createJob`, `createCleanup`, `deleteVM`, `rename`, `replaceDisk`,
  `registries`, `sharedFolders`, `icon`). Interpolate values with
  `privacy: .public`. **Never log secrets**: registry passwords are
  scrubbed with `RegistryCredentialScrubber` before reaching logs, sheets,
  or the clipboard; shared-folders logs record counts and tags, never host
  paths.
- **Comments.** `///` doc comments on public API stating responsibility,
  invariants, and rationale. `// MARK:` section headers in long files.
  Reference spec provenance ("Issue N", "finding N") when explaining why a
  decision was made.

## Testing

- **Swift Testing only** (`@Suite`, `@Test`, `#expect`, `Issue.record`). Do
  not introduce XCTest.
- **Hermetic tests.** No real `tart` and no GUI are required. Fake the CLI
  with the `StubBinary` helpers (`Tests/TartKitTests/TestSupport/`); inject
  closures (`Ops`, fetch) and isolated `UserDefaults(suiteName:)` instances;
  use `JobManager.awaitIdle` for quiescence. Capture real tart output in
  `Tests/TartKitTests/Fixtures/` when an error signature matters.
- **Naming.** Suite structs mirror production type names with a `Tests`
  suffix. Add tests for every new behavior, not just happy paths.

## Workflow

- Follow the `.sdd/` spec trail (PRD plus per-issue `issue.md`/`plan.md`/
  `review.md`/`validation.md`) when present.
- Commit style matches existing history: `feat: initial implementation`,
  `Walking skeleton: repo bootstrap and tart prerequisite detection`.
- Never commit `.build/`, `.swiftpm/`, `.sdd/`, `.codegraph/`, `.DS_Store`
  (gitignored). The untracked `control.sock` at the repo root is stray local
  tooling — do not add it.
