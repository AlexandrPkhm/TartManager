# Deployment

Tart Manager is a native macOS application deployed to end-user machines — a
GUI control center for the [tart](https://github.com/cirruslabs/tart) CLI. It
has no server-side components, no containers, and no cloud services of its
own. "Deployment" therefore means installing and configuring the app and its
prerequisites on each Mac that will manage VMs.

This document covers the production configuration surface only: environment
variables, the `tart` CLI dependency, registry access, error reporting, and
logging. Development setup is covered in [README.md](README.md); CI/CD and
packaging automation are separate concerns and out of scope here.

## Table of Contents

- [Deployment Model](#deployment-model)
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
  `deleteVM`, `rename`, `replaceDisk`, `registries`, `sharedFolders`.
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
| Storage availability | Configured path exists and is writable | Re-probed on every inventory poll; storage-unavailable state with recovery actions |
| Inventory polling | `tart list` every 3 seconds | Failures degrade to the storage-unavailable state, never modal errors |

Operational verification of a fresh deployment:

```sh
tart --version          # must report 2.0.0 or later
```

then launch the app: onboarding offers the storage location (or honors a
pre-seeded `storagePath`), no prerequisite banner is shown, and the VM list
populates. Use the `log stream` commands above to confirm healthy startup
(`storage` and `TartClient` categories) on machines under investigation.
