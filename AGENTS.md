# AGENTS.md

## Table of Contents

- [Project Overview](#project-overview)
- [Technical Context](#technical-context)
- [Project Structure](#project-structure)
- [Build And Test Commands](#build-and-test-commands)
- [Contribution Instructions](#contribution-instructions)
- [Code Guidelines](#code-guidelines)
    - [System Design](#system-design)
    - [Architecture](#architecture)
    - [Code Quality](#code-quality)
    - [Testing](#testing)
    - [Dependency Management](#dependency-management)
    - [Configuration & Documentation](#configuration--documentation)
    - [Other](#other)

## Project Overview

Tart Manager is a native macOS control center for locally installed
[`tart`](https://github.com/cirruslabs/tart) virtual machines. It lets people
list, run, stop, suspend, configure, create, clone, and snapshot VMs without
using the terminal. The application wraps the `tart` CLI; it does not implement
virtualization.

## Technical Context

- **Language/Version**: Swift tools version 6.0, compiled in Swift 5 language
  mode (`swiftLanguageModes: [.v5]`).
- **Primary Dependencies**: SwiftUI, AppKit, Foundation, Combine, and `os`;
  the package has no external package dependencies.
- **Storage**: `UserDefaults` stores application preferences. `tart` owns VM
  storage, which Tart Manager addresses through an injected `TART_HOME`.
- **Testing**: Swift Testing (`@Suite`, `@Test`, and `#expect`).
- **Target Platform**: macOS 14.0 and later.
- **Project Type**: Native macOS desktop application and Swift library.
- **Performance Goals**: N/A; no numeric goals are documented.
- **Constraints**: The GUI requires an installed `tart` 2.0.0+ binary, but
  builds and tests are hermetic. Swift 5 language mode restricts new syntax.
- **Scale/Scope**: A local, single-user control center for the host's tart VM
  inventory; it has no server component.

## Project Structure

```text
├── Package.swift                  # SwiftPM manifest; TartKit and TartManager targets
├── Sources/
│   ├── TartKit/                   # CLI client, policies, jobs, state, and logging
│   └── TartManager/               # SwiftUI application, views, menu bar, AppModel
│       └── Resources/             # Packaged app resources
├── Tests/
│   ├── TartKitTests/              # Hermetic TartKit suites, fixtures, and test support
│   │   ├── Fixtures/              # Captured tart output for analyzer tests
│   │   └── TestSupport/           # StubBinary and VM storage fixtures
│   └── TartManagerTests/          # AppModel and UI-policy unit tests
├── Assets/                        # Source artwork and Icon Composer source
├── Design/                        # Approved design references
├── Scripts/package.sh             # Release build, app bundle, signing, and DMG packaging
├── .github/workflows/ci.yml       # GitHub Actions test workflow
├── README.md                      # User-facing product guide
├── CHANGELOG.md                   # Release history and Unreleased changes
├── docs/
│   ├── DEVELOPMENT.md              # Contributor setup and development guide
│   └── DEPLOYMENT.md               # Packaging, signing, release, and operations reference
└── LICENSE                        # MIT license
```

## Build And Test Commands

- **Build and type check**: `swift build`
- **Run all tests deterministically**: `swift test --no-parallel`
- **Run one suite**: `swift test --no-parallel --filter <SuiteName>`
- **Run one test**:
  `swift test --no-parallel --filter "<SuiteName>.<testFunction>"`
- **Run the GUI**: `swift run`
- **Build the release binary**: `swift build -c release`
- **Package a release DMG**:
  `Scripts/package.sh --version <X.Y.Z> [--sign <identity>] [--notarize]`
- **Lint and format**: N/A. No linter or formatter configuration exists in
  this repository; do not invent verification commands.

## Contribution Instructions

- You MUST verify code with the configured compiler and test suite.

    - Run `swift build` for compilation and type checking.
    - Run `swift test --no-parallel` for the deterministic full test suite.
    - Do not substitute parallel `swift test`: cancellation-timing tests can
      flake in that mode.
    - No linter or formatter is configured; do not claim either was run.

- You MUST add or update Swift Testing cases for every changed behavior and
  keep the full deterministic suite passing.

- You MUST update `README.md`, `docs/DEVELOPMENT.md`, or
  `docs/DEPLOYMENT.md` when a change affects the audience each document serves.

- You MUST update the Project Structure section of this file when the
  repository structure changes.

- If a prompt asks for a refactoring or improvement, you MUST add the resulting
  reusable repository rule to the relevant Code Guidelines subsection.

- After completing a task, you MUST verify the changed code against the Code
  Guidelines in this file.

- You MUST follow the `.sdd/` PRD and issue trail when it is present.

- You MUST NOT commit `.build/`, `.swiftpm/`, `.sdd/`, `.codegraph/`,
  `dist/`, or `.DS_Store`.

## Code Guidelines

### System Design

- Treat Tart Manager as a long-lived desktop process: release temporary
  resources and terminate child-process work deliberately rather than relying
  on process exit.
- Keep UI state on the main actor. Use `@MainActor` for `AppModel`, inventory,
  job, and coordinator state that views observe.
- Keep blocking tart work off the UI thread with `Task.detached`, using
  `.userInitiated` for user actions and `.utility` for polling.
- Keep the main window, Settings scene, and menu-bar controls on the same
  `AppModel` so they use identical safety checks and error presentation.
- Persist user preferences through the validated `AppSettings` surface; do not
  let SwiftUI views write settings ad hoc.

### Architecture

- **Separation of Concerns**: Keep UI, orchestration, policy, and subprocess
  interaction in separate layers.
- **Single Responsibility Principle**: Give each file one dominant type or
  focused helper.
- **Dependency Direction**: `TartManager` depends on `TartKit`; `TartKit`
  never depends on the executable target.
- **Explicit Boundaries**: Expose only the TartKit API that the app target
  needs; do not reach through to implementation internals.
- **Data Flow Clarity**: Route user actions through `AppModel`, tested
  coordinators or jobs, and `TartClient`.
- **Minimize Coupling, Maximize Cohesion**: Keep policy and validation as
  focused, testable TartKit types.
- **Make Invalid States Impossible**: Use typed models, validation, and
  destructive-operation gates before launching a process.
- **Observability Built-in**: Normalize errors and record intentional
  decisions in unified logging.
- **Keep It Boring**: Prefer the existing Swift concurrency and SwiftPM
  patterns over new abstractions or dependencies.

This project uses a strict layered architecture:

```text
SwiftUI views, menu bar, Settings
             ↓
AppModel (thin UI wiring and presentation)
             ↓
TartKit policies, coordinators, inventory, and jobs
             ↓
TartClient, process runners, and command environment
             ↓
locally installed tart CLI
```

`TartManager` MUST remain thin plumbing. All tart CLI interaction belongs in
`TartClient`; policies, validation, race reconciliation, and job bodies belong
in tested TartKit types. The app target MUST NOT spawn a process directly.

Route subprocess failures through `TartClientError` and `TartErrorAnalyzer`
into `TartOperationError`, then present them via `AppModel.present(_:)` and
`ErrorReportSheet`. Preconditions and unknown errors MUST enter this same
normalization path; never show raw process failures to the user.

Cap captured stdout and stderr at 64 KiB per stream in normalized reports.
Pre-spawn preconditions MUST throw `TartClientError.commandFailed` with exit
code `-1`; wrap other unexpected errors in that error form with the operation
label so they follow the same reporting path.

Inject `TART_HOME` through `TartCommandEnvironment` into every
storage-touching tart command. Never depend on the GUI inheriting a shell
environment.

### Code Quality

- Name a file after its dominant type. Use immutable `struct` models with
  `Equatable` and `Sendable` where appropriate; use caseless enums for
  stateless helpers and `final class` for stateful services.
- Mark public only the TartKit surface needed by the executable target.
- Keep code compatible with Swift 5 language mode. Use extended regex literals
  (`#/…/#`), and assemble long interpolated log messages before logging when
  needed to avoid type-checker timeouts.
- Perform synchronous pre-checks before the first `await` to close
  double-click races. Lock-protected helpers must use `NSLock` and declare
  `@unchecked Sendable` only when the locking invariant is explicit.
- Use `///` comments on public APIs to document responsibility, invariants, and
  rationale. Use `// MARK:` sections in long files and cite issue or finding
  provenance when it explains a decision.
- Use the `Logger` extensions in `Sources/TartKit/Logging.swift` and the
  `app.TartManager` subsystem. Mark deliberately public values with
  `privacy: .public`; never log registry passwords or shared-folder host paths.
- Use the existing logging categories: `storage`, `settings`, `stop`,
  `suspend`, `errorReporting`, `TartClient`, `resources`, `clone`,
  `importJob`, `importCleanup`, `overcommit`, `snapshot`, `restore`,
  `createJob`, `createCleanup`, `deleteVM`, `rename`, `replaceDisk`,
  `registries`, `sharedFolders`, `icon`, and `clipboard`.
- Scrub registry credentials before errors, logs, sheets, or the clipboard
  receive them with `RegistryCredentialScrubber`. Shared-folder logs may record
  only counts and mount tags.
- Do not create silent no-ops: log and/or present every gate refusal, race
  reconciliation, and deliberate degradation. Re-verify destructive operations
  with `TypedConfirmationGate`, `RestoreGate`, `ReplaceDiskGuard`, or
  `CloneGuard` at the model boundary.

### Testing

- Use Swift Testing only (`@Suite`, `@Test`, `#expect`, and `Issue.record`);
  do not introduce XCTest.
- Place TartKit tests in `Tests/TartKitTests/` and executable-target tests in
  `Tests/TartManagerTests/`. Name suite structs after the production type with
  a `Tests` suffix.
- Keep tests hermetic. Use `StubBinary` for fake tart executables,
  `VMStorageFixture` for storage layouts, injected closures for collaborators,
  and isolated `UserDefaults(suiteName:)` instances for preferences.
- Use `JobManager.awaitIdle` to wait for jobs. Capture a real tart stderr
  fixture only when an analyzer signature requires it.
- Add tests for failure, validation, and reconciliation paths as well as happy
  paths, then run `swift test --no-parallel` before reporting completion.

### Dependency Management

- Keep the package dependency-free unless a standard-library or platform API
  cannot solve a substantial need.
- If a dependency becomes necessary, use a reputable, actively maintained
  source; pin its version explicitly and verify the latest stable version in
  its registry before adding it.
- Minimize dependency count and justify every addition because each dependency
  increases supply-chain risk and maintenance cost.

### Configuration & Documentation

- Keep runtime preference access in `AppSettings` and validate persisted
  storage paths before using them.
- Pass runtime command configuration through `TartCommandEnvironment`; do not
  read shell `TART_HOME` as application configuration.
- Treat registry credentials and notarization environment variables as secrets:
  never hardcode, log, or persist them outside the operating system's intended
  credential facilities.
- Keep user features in `README.md`, contributor procedures in
  `docs/DEVELOPMENT.md`, and packaging or operations details in
  `docs/DEPLOYMENT.md`.

### Other

- Match established commit-message style, such as `feat: add cache pruning
  settings` or `fix: apply theme changes reliably`.
- Open `Package.swift` directly in Xcode; this SwiftPM repository has no
  `.xcodeproj`.
