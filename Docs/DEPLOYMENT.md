# Deployment

Tart Manager is a native macOS application deployed to end-user machines — a
GUI control center for the [tart](https://github.com/openai/tart) CLI. It
has no server-side components, no containers, and no cloud services of its
own. "Deployment" therefore means installing and configuring the app and its
prerequisites on each Mac that will manage VMs.

This document covers the production configuration surface — environment
variables, the `tart` CLI dependency, registry access, error reporting, and
logging — and how to package the app into a distributable DMG. Development
setup is covered in [README.md](../README.md); CI/CD automation is out of scope
here.

## Table of Contents

- [Deployment Model](#deployment-model)
- [Packaging](#packaging)
- [Infrastructure Dependencies](#infrastructure-dependencies)
  - [Operating system](#operating-system)
  - [tart CLI](#tart-cli)
  - [Storage](#storage)
- [Environment Variables](#environment-variables)
  - [How variables flow to tart](#how-variables-flow-to-tart)
- [Configuration and Persistence](#configuration-and-persistence)
  - [UserDefaults keys](#userdefaults-keys)
  - [Pre-seeding for managed rollout](#pre-seeding-for-managed-rollout)
- [External Integrations](#external-integrations)
  - [OCI container registries](#oci-container-registries)
  - [Network requirements](#network-requirements)
- [Error Reporting](#error-reporting)
- [Logging](#logging)
  - [Unified logging configuration](#unified-logging-configuration)
  - [Child-process output](#child-process-output)
- [Health Checks and Monitoring](#health-checks-and-monitoring)

## Deployment Model

Each installation is a single macOS app running on one Mac. There is no
shared infrastructure: all state is local (UserDefaults, VM files managed by
tart under the configured storage path, and macOS Keychain entries owned by
tart). Deploying to N machines means repeating the same installation and
configuration on each, optionally pre-seeded by configuration management
(MDM or a provisioning script).

## Packaging

Tart Manager ships as a conventional macOS `.app` inside a disk image (DMG).
Because the project is Swift Package Manager only (no `.xcodeproj`), the
bundle must be assembled by hand — `swift build` produces a bare executable.
The packaged app does not bundle `tart` itself; the CLI remains a separate
prerequisite on the target machine (see [Infrastructure
Dependencies](#infrastructure-dependencies)).

The flow has four stages: release build, bundle assembly, code signing, and
DMG creation. The repository ships `Scripts/package.sh`, which automates all
of them:

```sh
Scripts/package.sh                    # ad-hoc signed; version = latest git tag (or 1.0.0)
Scripts/package.sh --version 1.2.3    # stamp a specific version
Scripts/package.sh --sign "Developer ID Application: Jane Doe (TEAM123)" --notarize
Scripts/package.sh --skip-build       # re-use the existing release binary
```

The artifact lands in `dist/TartManager-<version>.dmg`. With `--sign`,
adding `--notarize` notarizes and staples the finished DMG. Set
`NOTARY_PROFILE` to the name of a notarytool Keychain profile; the profile
keeps release credentials out of the packaging process's arguments.

The stages below are the manual equivalent of the script, documented for
reference and for custom toolchains. Every release must repeat all of them.

### Release build

```sh
swift build -c release
```

Find the release binary with `swift build -c release --show-bin-path`;
the output location varies between SwiftPM build systems. The app targets
Apple Silicon, matching tart's own host requirements.

### App bundle assembly

Create the standard macOS bundle layout and populate it:

```sh
APP="dist/Tart Manager.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$(swift build -c release --show-bin-path)/TartManager" "$APP/Contents/MacOS/TartManager"
xcrun actool Assets/AppIcon.icon \
    --compile "$APP/Contents/Resources" \
    --app-icon AppIcon --include-all-app-icons \
    --output-partial-info-plist dist/icon-info.plist \
    --target-device mac --minimum-deployment-target 14.0 --platform macosx
```

Full Xcode with Icon Composer support is required for packaging. The icon
source is `Assets/AppIcon.icon`: the transparent T is its foreground, with
a native light-gray background. Compilation produces `Assets.car` for system
appearance variants and `AppIcon.icns` for compatibility. Keep both files.
Packaged launches preserve the system-rendered Dock icon; bare `swift run`
launches use `Sources/TartManager/Resources/AppIcon.icns` as a static fallback.

Write `dist/Tart Manager.app/Contents/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>       <string>TartManager</string>
    <key>CFBundleIconFile</key>         <string>AppIcon</string>
    <key>CFBundleIconName</key>         <string>AppIcon</string>
    <key>CFBundleIdentifier</key>       <string>TartManager</string>
    <key>CFBundleName</key>             <string>TartManager</string>
    <key>CFBundleDisplayName</key>      <string>Tart Manager</string>
    <key>CFBundlePackageType</key>      <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>1.0.0</string>
    <key>CFBundleVersion</key>          <string>1</string>
    <key>LSMinimumSystemVersion</key>   <string>14.0</string>
    <key>NSHighResolutionCapable</key>  <true/>
</dict>
</plist>
```

The packaging script merges the icon compiler's partial Info.plist into the
app's Info.plist so both icon keys stay in sync with the compiled asset.

Set the two version keys to the release version being packaged. **The
`CFBundleIdentifier` must remain `TartManager`** (not reverse-DNS): all
settings persist in the `TartManager` defaults domain (see [Configuration
and Persistence](#configuration-and-persistence)), which is the domain the
bare `swift run` binary already uses. A reverse-DNS identifier would switch
`UserDefaults.standard` to a new domain and silently discard onboarding
state — the configured storage path and other settings — on machines that
previously ran the bare binary.

### Code signing

Sign the bundle before creating the DMG:

```sh
codesign --force --sign - "dist/Tart Manager.app"
```

`-` selects ad-hoc signing, which is sufficient for the developer's own
machine. For distribution to others, sign with a Developer ID certificate
and the hardened runtime instead:

```sh
codesign --force --options runtime --timestamp \
  --sign "Developer ID Application: <your identity>" "dist/Tart Manager.app"
```

This requires a paid Apple Developer account.

### DMG creation

```sh
mkdir -p dist/dmg-root
cp -R "dist/Tart Manager.app" dist/dmg-root/
ln -s /Applications dist/dmg-root/Applications

hdiutil create -volname "Tart Manager" -srcfolder dist/dmg-root -ov -format UDZO \
  dist/TartManager-1.0.0.dmg
```

The disk image contains the app and an `/Applications` symlink so users can
drag-install.

### Distribution notes

- **Gatekeeper.** Ad-hoc or unsigned builds are blocked as an "unidentified
  developer" on other machines; recipients must right-click → Open or run
  `xattr -cr "/Applications/Tart Manager.app"`. For a warning-free install,
  use Developer ID signing plus notarization.
- **Notarization.** With the Developer ID-signed app, notarize the finished
  DMG (not the app) and staple the ticket. Create a Keychain profile from an
  App Store Connect API key, then use that profile for submission:

  ```sh
  xcrun notarytool store-credentials "TartManagerNotary" \
    --key <path-to-api-key.p8> --key-id <key-id> --issuer <issuer-id>
  NOTARY_PROFILE=TartManagerNotary \
    Scripts/package.sh --version 1.0.0 \
    --sign "Developer ID Application: <your identity>" --notarize

  # Manual equivalent:
  xcrun notarytool submit dist/TartManager-1.0.0.dmg \
    --keychain-profile TartManagerNotary --wait
  xcrun stapler staple dist/TartManager-1.0.0.dmg
  ```

- **`tart` prerequisite.** The DMG never bundles `tart`. Target machines
  must install it first (`brew install cirruslabs/cli/tart`); otherwise the
  app shows its remediation banner at launch.

## Infrastructure Dependencies

| Dependency | Type | Version / requirement | Installation |
| --- | --- | --- | --- |
| macOS | Host OS | 14.0 or later, Apple Silicon (meet tart's own host requirements) | — |
| `tart` | CLI executable | `2.0.0` or later (`TartVersion.minimumSupported`) | Must be installed separately: `brew install cirruslabs/cli/tart` |
| Homebrew paths | Binary location | `/opt/homebrew/bin/tart` (Intel: `/usr/local/bin/tart`) | — |
| VM storage volume | Local filesystem | Existing, writable directory | Chosen at first launch (default `~/.tart`) |

There are no databases, cache servers, message queues, or object-storage
services. The app itself writes no data files outside UserDefaults and
temporary run logs; all VM state lives under the configured storage path and
is managed by the `tart` CLI.

### Operating system

- Minimum macOS **14.0** (`Package.swift` declares `.macOS(.v14)`).
- The host must satisfy tart's own requirements — tart runs on Apple Silicon
  Macs.

### tart CLI

Tart Manager never bundles `tart`; it must already be installed on the
target machine. On startup the app probes `tart --version` and shows a
banner with remediation commands when the prerequisite is unmet:

- Missing: `brew install cirruslabs/cli/tart`
- Outdated: `brew upgrade cirruslabs/cli/tart`

The binary is located in this order:

1. Explicit path override (Settings / tests)
2. Well-known Homebrew locations — `/opt/homebrew/bin/tart`,
   `/usr/local/bin/tart` (needed because GUI apps do not inherit the shell
   `PATH`)
3. Each directory of `PATH`, falling back to `/usr/bin:/bin` if `PATH` is
   unset

Upgrade notes: the supported surface requires tart `2.0.0+`; the minimum
version is a single domain constant (`TartVersion.minimumSupported`) that can
be bumped without changing deployment tooling.

### Storage

VM storage ("tart home") is a directory that must exist and be writable when
configured, and it is re-validated continuously. If the volume is unmounted
or becomes read-only, the app degrades to a storage-unavailable state rather
than failing operations. See [Configuration and
Persistence](#configuration-and-persistence) for how the path is set.

## Environment Variables

The app reads exactly one environment variable and sets exactly one for its
child processes. No secrets are passed through the environment.

| Variable | Purpose | Required | Set by | Example |
| --- | --- | --- | --- | --- |
| `TART_HOME` | Explicit tart home; overrides any inherited value for every storage-touching `tart` invocation, so GUI launches work without shell environment | No — managed internally | App (always overridden) | `/Volumes/VMStorage` |
| `PATH` | Search path used to find the `tart` binary after the Homebrew locations | No — read only | User session / launch environment | `/usr/bin:/bin` (fallback) |

Do not rely on a shell-configured `TART_HOME` taking effect: the app
overrides it with the configured storage path. The `tart --version`
prerequisite probe deliberately runs without the override.

### How variables flow to tart

Child `tart` processes start from the app's full inherited environment
(`ProcessInfo.processInfo.environment`) with `TART_HOME` overlaid on top.
There are no `.env` files and no application-specific environment
configuration files to provision on target machines.

## Configuration and Persistence

All settings persist in `UserDefaults` under the app's bundle domain
(`TartManager`). No configuration files are created on disk.

### UserDefaults keys

| Key | Purpose | Default / notes |
| --- | --- | --- |
| `storagePath` | Configured tart home ("VM storage") | `nil` until first-run onboarding completes; must be an existing, writable directory |
| `sshUser` | Username in the copyable SSH command | `"admin"` (empty value falls back) |
| `snapshotsFolder` | Folder for snapshot archives | Unset → "next to VM storage" |
| `pruneRetentionDays` | Cache-prune retention age in days | One of `7`, `14`, `30`; default `14` |
| `vmSharedFolders` | JSON-encoded map of VM name → host folder shares | Empty map by default |
| `firstRunReminderVMNames` | VM names for first-run reminders | Empty list |

Reset a key on a deployed machine with `defaults delete TartManager <key>`.

### Pre-seeding for managed rollout

For scripted or MDM deployments, write the storage path into the app's
defaults domain before first launch to skip onboarding:

```sh
defaults write TartManager storagePath -string "/Volumes/VMStorage"
```

The same mechanism applies to the other keys above. A pre-seeded
`storagePath` must point to a directory that exists and is writable, or the
app will show the storage-unavailable state.

## External Integrations

Tart Manager has no OAuth, API keys, or webhooks, and it owns no network
endpoints. The only external system it talks to — through the `tart` CLI — is
OCI container registries.

### OCI container registries

- **Purpose**: pull VM images (e.g. `ghcr.io/cirruslabs/...`) and push
  created VMs.
- **Credentials**: registry host + username + password/token, entered in
  Settings → Registries (`tart login <host> --username <user>
  --password-stdin`). The password is delivered to tart over stdin and is
  **never stored by Tart Manager**; tart keeps the session in the macOS
  **Keychain**.
- **Sign out**: `tart logout <host>` removes tart's stored credentials for
  that host.
- **Secrets handling**: credentials live only in the Keychain (managed by
  tart). No secret may ever be placed in UserDefaults, the environment, or
  the repository.

### Network requirements

Production machines must allow outbound HTTPS from the `tart` process to:

- OCI registries used by the fleet (e.g. `ghcr.io`)
- IPSW restore-image endpoints, when VMs are created from IPSW (`tart create
  --from-ipsw`)

All such traffic is initiated by the tart CLI, not by the app binary.

## Error Reporting

No third-party crash/error SDK (Sentry, Bugsnag, Rollbar, etc.) is
integrated, so there is no DSN or error-service configuration to provision.

Failures are handled in-app instead:

- Every failed tart operation is normalized into a single report type
  (operation, message, hint, exit code, raw details) and shown in a standard
  report sheet with **Copy Details** for bug reports.
- Raw stdout/stderr are captured per stream up to **64 KiB** each.
- Known failure signatures (e.g. the cross-version IPSW restore refusal) are
  tagged with an explanatory hint.
- Every normalized failure is also written to unified logging under the
  `errorReporting` category, so dismissed reports stay diagnosable on the
  machine (see [Logging](#logging)).

Collecting reports from a deployed machine:

```sh
log show --last 24h --predicate 'subsystem == "app.TartManager" AND category == "errorReporting"'
```

## Logging

The app logs to the macOS unified logging system via `os.Logger`. It writes
no log files of its own.

### Unified logging configuration

- **Subsystem**: `app.TartManager` (all categories); the prerequisite probe
  is the one exception, using subsystem `org.tartmanager.TartKit`, category
  `PrerequisiteChecker`.
- **Categories**: `storage`, `settings`, `stop`, `suspend`, `errorReporting`,
  `TartClient`, `resources`, `clone`, `importJob`, `importCleanup`,
  `overcommit`, `snapshot`, `restore`, `createJob`, `createCleanup`,
  `deleteVM`, `rename`, `replaceDisk`, `registries`, `sharedFolders`, `icon`.
- **Levels**: call sites use `notice`, `info`, `debug`, `warning`, and
  `error`; there is no runtime level switch in the app. To enable
  debug-level output on a production machine for triage:

  ```sh
  sudo log config --mode "level:debug" --subsystem "app.TartManager"
  ```

  (reset with `sudo log config --mode "level:default" --subsystem
  "app.TartManager"`).

Live and historical inspection:

```sh
# Live stream of all Tart Manager logging
log stream --predicate 'subsystem == "app.TartManager"'

# Per-category examples
log stream --predicate 'subsystem == "app.TartManager" AND category == "stop"'
log stream --predicate 'subsystem == "app.TartManager" AND category == "registries"'
```

### Child-process output

Output from spawned `tart` processes is handled in three ways:

| Operation type | Handling |
| --- | --- |
| Quick commands (`list`, `get`, …) | Both streams captured to completion; 10 s default timeout |
| Long-running jobs (clone, import, prune, …) | Streamed with the combined tail capped at **64 KiB** (`TextAccumulator`) |
| Detached `tart run` sessions | stdout/stderr redirected to a temporary file `tartmanager-run-<UUID>.log` in the system temp directory, removed after the 5 s early-failure window |

Stale run logs are swept at app launch, so no run logs persist beyond the
early-failure window.

## Health Checks and Monitoring

Tart Manager is a desktop app with no HTTP server, so there are no
`/health`-style endpoints. Runtime health is expressed through three
in-app signals instead:

| Signal | What it checks | Behavior on failure |
| --- | --- | --- |
| Prerequisite status | `tart` present and `>= 2.0.0` | Remediation banner (`brew install` / `brew upgrade`) |
| Storage availability | Configured path exists and is writable | Re-probed on every inventory poll; while unavailable, re-probed every 30 seconds, on app activation, and on Retry; storage-unavailable state with recovery actions |
| Inventory polling | `tart list` every 3 seconds | Paused while storage is unavailable; failures degrade to the storage-unavailable state, never modal errors |

Operational verification of a fresh deployment:

```sh
tart --version          # must report 2.0.0 or later
```

then launch the app: onboarding offers the storage location (or honors a
pre-seeded `storagePath`), no prerequisite banner is shown, and the VM list
populates. Use the `log stream` commands above to confirm healthy startup
(`storage` and `TartClient` categories) on machines under investigation.
