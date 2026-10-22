# Tart Manager — Development Guide

This guide covers everything you need to set up, run, and contribute to Tart
Manager. User-facing documentation is in [`README.md`](../README.md); code
guidelines and architecture rules are in [`AGENTS.md`](../AGENTS.md).

## Table of Contents

- [Table of Contents](#table-of-contents)
- [Prerequisites](#prerequisites)
  - [Swift toolchain and Xcode](#swift-toolchain-and-xcode)
  - [tart CLI](#tart-cli)
  - [Other tools](#other-tools)
- [Getting Started](#getting-started)
  - [Clone the repository](#clone-the-repository)
  - [Build the project](#build-the-project)
  - [Configure the environment](#configure-the-environment)
  - [Run the app](#run-the-app)
  - [Open in Xcode](#open-in-xcode)
- [Development Workflow](#development-workflow)
  - [Branching and pull requests](#branching-and-pull-requests)
  - [Code style](#code-style)
  - [Testing](#testing)
  - [Building release binaries](#building-release-binaries)
  - [Debugging and IDE configuration](#debugging-and-ide-configuration)
- [Common Tasks](#common-tasks)
  - [Running a specific test](#running-a-specific-test)
  - [Adding a new tart operation](#adding-a-new-tart-operation)
  - [Adding a new setting](#adding-a-new-setting)
  - [Watching the app's logs](#watching-the-apps-logs)
  - [Resetting development state](#resetting-development-state)
  - [Testing an in-app update locally](#testing-an-in-app-update-locally)
- [Troubleshooting](#troubleshooting)
  - [Flaky tests in parallel mode](#flaky-tests-in-parallel-mode)
  - [Swift 5 language mode compilation limits](#swift-5-language-mode-compilation-limits)
  - [tart is missing or too old](#tart-is-missing-or-too-old)
  - [VM storage unavailable](#vm-storage-unavailable)
  - [GUI cannot see shell environment variables](#gui-cannot-see-shell-environment-variables)
  - [Untracked `control.sock` at the repo root](#untracked-controlsock-at-the-repo-root)
- [Additional Resources](#additional-resources)

## Prerequisites

Tart Manager is a Swift Package Manager project targeting macOS 14+. Its only
package dependency is [Sparkle](https://github.com/sparkle-project/Sparkle)
**2.10.0**, the in-app updater, pinned with `exact:` in `Package.swift` and
locked in `Package.resolved`. Only the `TartManager` executable target links
it; `TartKit` does not. The first `swift build` downloads Sparkle's binary
framework, so it needs network access. Later builds and `swift test` work
offline from the cache in `.build/`.

To change the Sparkle version, edit the `exact:` version in `Package.swift`,
run `swift package resolve`, and commit both files. Read the Sparkle release
notes first, and repeat the local update test in
[Testing an in-app update locally](#testing-an-in-app-update-locally).

### Swift toolchain and Xcode

- **Swift 6.x toolchain** — `Package.swift` declares
  `// swift-tools-version:6.0`, so Swift 6.0 or newer is required. The
  package compiles in **Swift 5 language mode**
  (`swiftLanguageModes: [.v5]`); see
  [Swift 5 language mode compilation limits](#swift-5-language-mode-compilation-limits).
- **Xcode 16.0 or later** (or an equivalent Swift 6 toolchain such as
  Command Line Tools + Swift.org toolchain). The repository has been
  verified with **Xcode 27.0 (Build 27A266a)** and **Swift 6.4**
  (`swiftlang-6.4.0.34.1`).

Check your versions with:

```sh
swift --version
xcodebuild -version
```

### tart CLI

The app wraps the locally installed `tart` binary; it does not bundle it.
You need tart **2.0.0 or newer** (the app's `TartVersion.minimumSupported`
floor). Install or upgrade with Homebrew:

```sh
brew install cirruslabs/cli/tart
brew upgrade tart   # to update
```

The build and the entire test suite are hermetic — neither requires tart to
be installed. Only `swift run` (the live GUI) does. A `swift run` build has
no bundled tart, so it uses the Path source: tart is located through
`/opt/homebrew/bin/tart`, `/usr/local/bin/tart`, or `PATH`, unless you
choose a file in Settings → General → Tart. Settings shows Bundled as "Not
available in this build".

### Other tools

- **Git** — for cloning and contributing.
- **macOS 14 (Sonoma) or later** — the deployment target is
  `platforms: [.macOS(.v14)]` and the app uses macOS 14+ SwiftUI APIs
  (`NavigationSplitView`, `ContentUnavailableView`, two-parameter
  `onChange(of:)`, …).

## Getting Started

### Clone the repository

```sh
git clone <repository-url> TartManager
cd TartManager
```

(No remote is configured in this working copy, so the URL above is a
placeholder — substitute your fork's URL.)

### Build the project

```sh
swift build
```

The first build fetches Sparkle (see [Prerequisites](#prerequisites)), then
compiles the local sources. Find the debug binary with
`swift build --show-bin-path`.

### Configure the environment

- **No environment variables or config files are needed** to build or test.
  The app is fully self-configuring on first run: an onboarding sheet asks
  where VMs live and persists the choice.
- The app never reads `TART_HOME` from your shell; it **injects** it into
  every storage-touching tart invocation so GUI launches behave identically
  to terminal ones.
- The only variable the code consults is `PATH` (tart binary discovery,
  falling back to `/usr/bin:/bin`).
- All preferences live in `UserDefaults` under the `TartManager` domain:
  `storagePath`, `sshUser`, `snapshotsFolder`, `pruneRetentionDays`,
  `vmSharedFolders`, `firstRunReminderVMNames`, `tartSource`
  (`bundled` or `installed`), and `tartCustomPath`.

### Run the app

```sh
swift run
```

`TartManager` is the only executable product, so `swift run` builds and
launches the GUI app (a logged-in GUI session is required). A `swift run`
binary has no bundle `Info.plist`, so the updater does not start: Settings →
About shows "Updates are not available in development builds.", and the
`updates` log category records the missing keys. To reset the
app to its out-of-the-box state for development:

```sh
defaults delete TartManager storagePath
```

To see the one-time tart source question again, remove the stored source:

```sh
defaults delete TartManager tartSource
```

### Test the bundled tart

The packaged app embeds tart at `Contents/Helpers/tart.app`. To test the
Bundled source before packaging adds it:

1. Package a DMG with `Scripts/package.sh` (see
   [DEPLOYMENT.md](DEPLOYMENT.md)), open it, and copy **Tart Manager** to a
   writable folder, for example `~/Desktop`.
2. Copy a signed `tart.app` into the copy. Homebrew keeps one in
   `$(brew --prefix tart)/libexec/tart.app`:

   ```sh
   ditto "$(brew --prefix tart)/libexec/tart.app" \
       ~/Desktop/"Tart Manager.app"/Contents/Helpers/tart.app
   ```

3. Re-sign only the outer app. Never use `--deep`: it replaces the tart
   signature that the bundled-tart check requires.

   ```sh
   codesign --force --sign - ~/Desktop/"Tart Manager.app"
   ```

4. Open that copy. Settings → General → Tart now offers Bundled.

### Open in Xcode

```sh
open Package.swift        # or: xed .
```

Xcode opens the Swift package directly — there is no `.xcodeproj`. Shared
schemes (`TartManager`, `TartKit`, `TartManager-Package`) are generated
automatically; press ⌘R to run the app under the debugger.

## Development Workflow

### Branching and pull requests

1. Create a feature branch off `main`.
2. Follow the architecture rules and code style in
   [`AGENTS.md`](../AGENTS.md); add tests for every new behavior.
3. Verify before pushing:

   ```sh
   swift build
   swift test --no-parallel
   ```

4. Open a pull request. `.github/CODEOWNERS` requests the maintainer's
   review on every pull request. CI does not run on pull requests, so the
   local verification in step 3 is the only test gate.

CI (`.github/workflows/ci.yml`) runs only when a `vX.Y.Z` tag is pushed:
job `test` on `macos-latest` executes `swift --version` then
`swift test --no-parallel`, and fails after 20 minutes. The workflow is
currently disabled in the repository's Actions settings.

Commit messages follow the existing style: `feat: initial implementation`,
`Walking skeleton: repo bootstrap and tart prerequisite detection`.

### Code style

Code guidelines — architecture rules, error normalization, logging
categories, concurrency, and Swift 5 language mode constraints — are
documented in [`AGENTS.md`](../AGENTS.md). Follow it; it is the authoritative
style reference for this repository.

### Testing

All tests use Swift Testing (`@Suite` / `@Test`) and are hermetic: no real
`tart`, no GUI, no network. The fake CLI is built with the `StubBinary`
helper (`Tests/TartKitTests/TestSupport/`).

Run the full suite — **always with `--no-parallel`**, the project's
deterministic mode:

```sh
swift test --no-parallel
```

Expected: all suites green (currently ~450 tests in ~75 suites). Parallel
`swift test` flakes on cancellation-timing races — see
[Flaky tests in parallel mode](#flaky-tests-in-parallel-mode).

Useful variants:

```sh
swift test --no-parallel --filter TartKitTests      # one target
swift test --no-parallel --filter TartVersionTests  # one suite
swift test --no-parallel --filter "TartVersionTests.definesMinimumSupportedFloor"  # one test
```

### Building release binaries

```sh
swift build -c release
```

The optimized binary is `.build/release/TartManager`. Everything else about
shipping and production configuration — installation targets, environment
variables, registries, logging on deployed machines — is documented in
[`DEPLOYMENT.md`](DEPLOYMENT.md).

### Debugging and IDE configuration

- Run under Xcode (`open Package.swift`, ⌘R) for breakpoints, SwiftUI
  previews, and Instruments.
- The app's diagnostics are unified logging. Stream them live:

  ```sh
  log stream --level info --predicate 'subsystem == "app.TartManager"'
  ```

  Feature-specific categories include `stop`, `suspend`, `replaceDisk`,
  `overcommit`, `registries`, `clipboard`, and `updates`; the full category
  list is in `Sources/TartKit/Logging.swift`.
- Dismissed error reports remain diagnosable with the same predicate —
  every normalized failure is logged.

## Common Tasks

### Running a specific test

Use `--filter` with the suite or `SuiteName.testFunction` (see
[Testing](#testing)). Suite structs mirror production types with a `Tests`
suffix, e.g. `TartClientTests`, `AppModelTests`.

### Adding a new tart operation

Follow the layered structure — the app target never touches the CLI:

1. Add the command method to `TartClient` (`Sources/TartKit/`) and map its
   failures to `TartClientError`.
2. Wrap policies (gates, validation, reconciliation) as pure, tested types;
   orchestrate state in a `@MainActor` coordinator or job body.
3. Wire `AppModel` to the new surface and add a thin SwiftUI view.
4. Add `StubBinary`-based tests mirroring the new types, then
   `swift test --no-parallel`.

### Adding a new setting

1. Add the key to `AppSettings` (`Sources/TartKit/AppSettings.swift`) with
   its default and validation.
2. Persist through the single validated write path in `AppModel` and log
   the transition (category `settings`).
3. Add an `AppSettingsTests` case with an isolated
   `UserDefaults(suiteName:)`.

### Watching the app's logs

```sh
# everything the app logs
log stream --level info --predicate 'subsystem == "app.TartManager"'

# one category, e.g. clone jobs
log stream --predicate 'subsystem == "app.TartManager" AND category == "clone"'
```

### Resetting development state

```sh
defaults delete TartManager storagePath       # re-trigger onboarding
defaults delete TartManager sshUser           # reset per-key settings
```

The `storagePath` reset is the common one: it restores the first-run
onboarding flow without touching other preferences.

### Testing an in-app update locally

Use a throwaway signing key and a local feed. Never sign test builds with
the production key, and never commit the test values.

1. Create a throwaway key and print its public key:

   ```sh
   BIN=.build/artifacts/sparkle/Sparkle/bin
   $BIN/generate_keys --account tartmanager-test
   $BIN/generate_keys --account tartmanager-test -p
   ```

2. Package an older and a newer version, for example `1.2.0` and `1.2.1`,
   each into its own output folder:

   ```sh
   Scripts/package.sh --version 1.2.0 -o /tmp/tm-old
   Scripts/package.sh --version 1.2.1 -o /tmp/tm-new
   ```

3. Mount each DMG and copy **Tart Manager.app** out with `ditto`. In each
   copy, set `SUFeedURL` to `http://127.0.0.1:8000/appcast.xml` and
   `SUPublicEDKey` to the throwaway public key with
   `/usr/libexec/PlistBuddy`. Then re-sign it in the order from
   [Code signing](DEPLOYMENT.md#code-signing), and put the newer app in a new
   DMG in the feed folder `/tmp/tm-feed`.
4. Sign the feed and serve it:

   ```sh
   $BIN/generate_appcast --account tartmanager-test --download-url-prefix http://127.0.0.1:8000/ /tmp/tm-feed
   python3 -m http.server 8000 --bind 127.0.0.1 --directory /tmp/tm-feed
   ```

5. Copy the older app to `/Applications` with `ditto` (no quarantine
   attribute), open it, and click **Check for Updates** in Settings → About.
   Sparkle installs the newer version and relaunches the app.
6. Delete the throwaway key from the login Keychain:

   ```sh
   security delete-generic-password -s https://sparkle-project.org -a tartmanager-test
   ```

## Troubleshooting

### Flaky tests in parallel mode

**Symptom:** intermittent failures in `StreamingProcessTests`,
`TartClientExportTests`, `TartClientCreateIPSWTests`, `TartClientPruneTests`,
`JobManagerTests`, `CloneJobOutcomeTests`, or `AppModelTests` under plain
`swift test`.

**Cause:** these suites assert cancellation timing, which is wall-clock
dependent and races when tests run in parallel.

**Fix:** run `swift test --no-parallel`. Do not report these flakes as
product bugs.

### Swift 5 language mode compilation limits

- **Bare regex literals are not enabled.** Use extended literals:
  `#/…/#` instead of `/…/`.
- **Long interpolated `Logger` calls can exceed the type checker's budget.**
  Assemble the string by concatenation first, then pass it to the logger.
  Existing code documents this in comments.

Keep new code compiling in Swift 5 language mode — the package sets
`swiftLanguageModes: [.v5]`.

### tart is missing or too old

**Symptom:** the app shows a prerequisite banner instead of the VM list.

**Cause:** the selected tart is not installed, is not on `PATH`, cannot run
(a custom path), is damaged (a bundled tart with a bad signature), or is
older than the supported floor (`TartVersion.minimumSupported` = 2.0.0).
The banner names the case. To see why each source failed, read the
`tartRuntime` log:

```sh
log show --last 10m \
    --predicate 'subsystem == "app.TartManager" AND category == "tartRuntime"'
```

**Fix:**

```sh
brew install cirruslabs/cli/tart   # or: brew upgrade tart
which tart && tart --version
```

### VM storage unavailable

**Symptom:** the app shows a "VM storage unavailable" state naming a path.

**Cause:** the configured volume is unmounted or read-only.

**Fix:** re-mount the volume and click Retry, or choose another folder. To
re-run onboarding from scratch:

```sh
defaults delete TartManager storagePath
```

### GUI cannot see shell environment variables

This is by design, not a bug: GUI apps don't inherit shell profiles. The
app compensates in two places — it locates the tart binary via
`/opt/homebrew/bin/tart` → `/usr/local/bin/tart` → `PATH`, and it injects
`TART_HOME` into every storage-touching invocation
(`TartCommandEnvironment`). If tart behaves differently in the GUI than in
your terminal, compare the exact command and environment in the error
report sheet (Copy Details) — never "fix" it by mutating shell dotfiles.

### Untracked `control.sock` at the repo root

A stray Unix domain socket from unrelated local tooling may appear at the
repo root. It is not covered by `.gitignore`. Delete it (it is recreated
by its owner tool) and don't `git add -A` blindly:

```sh
rm control.sock
```

## Additional Resources

- [`README.md`](../README.md) — user-facing overview and feature documentation.
- [`AGENTS.md`](../AGENTS.md) — code guidelines and architecture rules.
- [`DEPLOYMENT.md`](DEPLOYMENT.md) — production configuration and rollout.
- [`LICENSE`](LICENSE) — MIT.
- [tart](https://github.com/openai/tart) — the wrapped CLI's repository.
- `.sdd/` (gitignored) — the spec-driven-development trail: PRD plus
  per-issue plan/review/validation documents.
