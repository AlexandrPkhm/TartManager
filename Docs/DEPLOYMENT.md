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
- [In-App Updates](#in-app-updates)
    - [Signing key](#signing-key)
    - [Release procedure](#release-procedure)
    - [Key loss and key leak](#key-loss-and-key-leak)
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
The packaged app embeds the unchanged upstream `tart.app` at
`Contents/Helpers/tart.app`, so target machines need no separate tart (see
[Bundled tart](#bundled-tart)).

Before it builds, the script looks for a newer tart release (see [Release
procedure](#release-procedure)). The flow then has five stages: release
build, bundled tart, bundle assembly, code signing, and DMG creation. An
optional sixth stage writes the signed update feed (see [In-App
Updates](#in-app-updates)). The repository ships `Scripts/package.sh`, which
automates all of them:

```sh
Scripts/package.sh                    # ad-hoc; version = latest tag without its v (or 1.0.0)
Scripts/package.sh --version 1.2.3    # stamp a specific version
Scripts/package.sh --version 1.2.3 --appcast   # also write dist/updates/
Scripts/package.sh --sign "Developer ID Application: Jane Doe (TEAM123)" --notarize
Scripts/package.sh --skip-build       # re-use the existing release binary
Scripts/package.sh --skip-tart-check  # offline: no newer-tart check
Scripts/package.sh --check-tart       # run only the newer-tart check
```

| Option | Effect |
| --- | --- |
| `--skip-tart-check` | Does not look for a newer tart. Prints `==> Skipped the tart release check (--skip-tart-check)`. |
| `--check-tart` | Runs only the newer-tart check, then exits. Needs no `--version`. |
| `--tart-pin-file PATH` | Reads the tart pin from `PATH`. The default is `Scripts/tart-pin.env`. |

The artifact lands in `dist/TartManager-<version>.dmg`, and the last line
prints its size (`==> Done: <path> (<size> MB)`). With tart 2.41.1 the DMG is
about 30 MB, and the unpacked app is about 85 MB. With `--sign`,
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

### Bundled tart

The script embeds one pinned tart release from
[openai/tart](https://github.com/openai/tart). These files control it:

| File | Content |
| --- | --- |
| `Scripts/tart-pin.env` | `TART_VERSION` and `TART_SHA256` of the release asset `tart.tar.gz`. |
| `Scripts/tart-LICENSE.txt` | The `LICENSE` of the pinned release, byte for byte. Tart 2.41.1 uses FSL-1.1-ALv2. |
| `.build/tart-cache/<version>/` | The downloaded `tart.tar.gz` and `tart_<version>_checksums.txt`. Git ignores `.build/`. |

For each build, the script does these steps before it assembles the bundle:

1. Uses the cached archive, or downloads it with
   `gh release download <version> --repo openai/tart`. It deletes a cached
   archive that does not match `TART_SHA256` and downloads it again.
2. Checks the archive against `TART_SHA256` and against the line for
   `tart.tar.gz` in the release checksums file.
3. Extracts the archive into a new, empty folder in the staging folder,
   never into the repository.
4. Verifies `tart.app`:
    - `codesign --verify --strict` passes.
    - The team is `9M2P8L4D89` (Cirrus Labs, Inc.), the same value as
      `BundledTartVerifier.expectedTeamIdentifier`.
    - `spctl --assess --type execute` accepts it.
    - `tart --version` prints the pinned version.
    - `Contents/embedded.provisionprofile` exists.
5. Compares the archive `LICENSE` with `Scripts/tart-LICENSE.txt`.

Any failed check stops the build. The bundle assembly then copies
`tart.app` with `ditto` to `Contents/Helpers/tart.app` and the license to
`Contents/Resources/tart-LICENSE.txt`. The About tab shows the license.

The script needs network access and a signed-in `gh` when the cache does not
have the pinned archive.

### App bundle assembly

Create the standard macOS bundle layout and populate it:

```sh
APP="dist/Tart Manager.app"
BIN="$(swift build -c release --show-bin-path)"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cp "$BIN/TartManager" "$APP/Contents/MacOS/TartManager"
ditto "$BIN/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" \
    "$APP/Contents/Frameworks/Sparkle.framework/XPCServices"
install_name_tool -add_rpath "@executable_path/../Frameworks" \
    "$APP/Contents/MacOS/TartManager"
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

`Sparkle.framework` is the in-app updater. SwiftPM puts it next to the
release binary. Tart Manager is not sandboxed, so the bundle does not keep
Sparkle's XPC services. The release binary has no rpath to
`Contents/Frameworks`, so `install_name_tool` adds one. The finished bundle
layout is:

```text
Tart Manager.app/Contents/
├── Info.plist
├── MacOS/TartManager
├── Frameworks/Sparkle.framework/Versions/B/
│   ├── Sparkle
│   ├── Autoupdate
│   ├── Updater.app
│   └── Resources/
└── Resources/              # Assets.car, AppIcon.icns
```

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
    <key>CFBundleShortVersionString</key> <string>1.2.0</string>
    <key>CFBundleVersion</key>          <string>1.2.0</string>
    <key>LSMinimumSystemVersion</key>   <string>14.0</string>
    <key>NSHighResolutionCapable</key>  <true/>
    <key>SUFeedURL</key>                <string>https://github.com/AlexandrPkhm/TartManager/releases/latest/download/appcast.xml</string>
    <key>SUPublicEDKey</key>            <string>fji7wp6SDYVkEnj4+Fv8kN6J+6NrtSAr1w10K1zHzdA=</string>
    <key>SUEnableAutomaticChecks</key>  <true/>
    <key>SUEnableSystemProfiling</key>  <false/>
    <key>SUScheduledCheckInterval</key> <integer>86400</integer>
</dict>
</plist>
```

The packaging script merges the icon compiler's partial Info.plist into the
app's Info.plist so both icon keys stay in sync with the compiled asset.

Set both version keys to the release version being packaged, for example
`1.2.0`. Sparkle compares `CFBundleVersion` with `sparkle:version` in the
feed, so `CFBundleVersion` must equal `CFBundleShortVersionString`. Releases
before 1.2.0 used `CFBundleVersion` `1`.

The `SU*` keys configure Sparkle: the feed URL, the EdDSA public key that
verifies every update, a daily automatic check that is on by default, and no
system profile. **The
`CFBundleIdentifier` must remain `TartManager`** (not reverse-DNS): all
settings persist in the `TartManager` defaults domain (see [Configuration
and Persistence](#configuration-and-persistence)), which is the domain the
bare `swift run` binary already uses. A reverse-DNS identifier would switch
`UserDefaults.standard` to a new domain and silently discard onboarding
state — the configured storage path and other settings — on machines that
previously ran the bare binary.

### Code signing

Sign the nested Sparkle code from the inside out, then the bundle, and
verify the result:

```sh
F="dist/Tart Manager.app/Contents/Frameworks/Sparkle.framework"
codesign --force --sign - "$F/Versions/B/Autoupdate"
codesign --force --sign - "$F/Versions/B/Updater.app"
codesign --force --sign - "$F"
codesign --force --sign - "dist/Tart Manager.app"
codesign --verify --strict --verbose=2 "dist/Tart Manager.app"
```

Do not sign `Contents/Helpers/tart.app`. It keeps its own Developer ID
signature, entitlements, provisioning profile, and notarization. Upstream
does not staple a ticket to `tart.app`, so Gatekeeper checks its
notarization online. After
it signs the bundle, the script verifies `tart.app` again with
`codesign --verify --strict` and checks that its team is still `9M2P8L4D89`:

```sh
T="dist/Tart Manager.app/Contents/Helpers/tart.app"
codesign --verify --strict --verbose=2 "$T"
codesign -dv "$T" 2>&1 | grep TeamIdentifier   # TeamIdentifier=9M2P8L4D89
```

`-` selects ad-hoc signing. Do not use `codesign --deep`: it signs nested
code in an unspecified order and with the wrong options. Do not add
`--options runtime` to an ad-hoc build: Library Validation in the hardened
runtime refuses the ad-hoc `Sparkle.framework`, and the app crashes at
launch.

For distribution with a Developer ID certificate, sign the same four paths in
the same order with the hardened runtime:

```sh
codesign --force --options runtime --timestamp \
  --sign "Developer ID Application: <your identity>" "<path>"
```

This requires a paid Apple Developer account. The EdDSA key does not change
when you move to Developer ID, so in-app updates continue to work.

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
  developer" on other machines. On the first install, recipients open
  **System Settings** → **Privacy & Security** and click **Open Anyway**
  (macOS 15 and later), Control-click → **Open** (macOS 14), or run
  `xattr -cr "/Applications/Tart Manager.app"`. In-app updates download with
  no quarantine attribute, so they open with no warning. For a warning-free
  first install, use Developer ID signing plus notarization.
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

- **Nested signatures.** An ad-hoc build has an ad-hoc outer app and a
  nested `tart.app` that keeps its Developer ID signature and notarization.
  The outer app is notarized only with `--sign` and `--notarize`.
- **Bundled tart.** Target machines need no separate tart. A user can still
  select an installed tart in Settings → General → **Tart**.

## In-App Updates

Tart Manager uses [Sparkle](https://sparkle-project.org) 2.10.0 to update
itself. The app reads the feed at
`https://github.com/AlexandrPkhm/TartManager/releases/latest/download/appcast.xml`,
a release asset of the latest GitHub release. The feed lists only the latest
release, and the DMG is both the first-install file and the update archive.

Without Apple signing, the only trust anchor for an update is an EdDSA
(Ed25519) signature. `generate_appcast` signs the DMG with the private key,
and the app verifies it with `SUPublicEDKey`. Sparkle refuses an archive that
does not match.

### Signing key

The Sparkle tools are in `.build/artifacts/sparkle/Sparkle/bin/` after
`swift build`. Create the key pair one time, on the maintainer's Mac:

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys
```

`generate_keys` saves the private key in the login Keychain and prints the
public key. Put the public key in `SPARKLE_PUBLIC_ED_KEY` in
`Scripts/package.sh`. To print it again, run `generate_keys -p`.

Back up the private key offline, for example in a password manager, then
delete the export file:

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x tartmanager-sparkle-private-key
```

> **Warning:** Never commit the private key, store it in CI, or send it to
> another person. Anyone with the key can sign an update that every user
> installs.

### Release procedure

1. Check for a newer tart, and commit a pin bump before the release:

   ```sh
   Scripts/package.sh --check-tart
   ```

   The script prints the pinned and latest versions. When the latest
   release is newer, it prints the release URL and asks
   `Bump bundled tart to X.Y.Z? [y/N]`. On `y` it downloads and verifies the
   release, then writes `Scripts/tart-pin.env`. If the license text changed,
   it shows the diff and asks
   `The tart license text changed. Accept the new license? [y/N]` before it
   writes `Scripts/tart-LICENSE.txt` and the pin. Any other answer, or no
   terminal, keeps the pin. The script never commits. Commit the bump on its
   own with a CHANGELOG entry, for example
   `chore: bump bundled tart to X.Y.Z`.

   > **Warning:** An agent that runs a release build must ask the maintainer
   > in chat before it answers `y`.

   Each release build (step 3) runs the same check. Use `--skip-tart-check`
   for an offline build.
2. Move the `## Unreleased` entries in `CHANGELOG.md` to a `## X.Y.Z - DATE`
   section. The script uses that section as the release notes.
3. Build, sign, and write the feed:

   ```sh
   Scripts/package.sh --version X.Y.Z --appcast
   ```

   macOS asks for access to the signing key in the login Keychain.
   `--appcast` writes `dist/updates/` from an empty folder: the DMG,
   `TartManager-X.Y.Z.md` with the release notes, and `appcast.xml`. The
   download URL prefix is
   `https://github.com/AlexandrPkhm/TartManager/releases/download/vX.Y.Z/`.
   The script fails when the CHANGELOG section is missing or empty, or when
   `appcast.xml` has no `sparkle:edSignature`.
4. Open the packaged app one time, to check that it launches.
5. Publish the release:

   ```sh
   gh release create vX.Y.Z dist/TartManager-X.Y.Z.dmg dist/updates/appcast.xml --notes-file dist/updates/TartManager-X.Y.Z.md
   ```

The tag must be `vX.Y.Z`, because the feed's download URL contains it. Users
on 1.0.0 and 1.1.0 have no updater and must install 1.2.0 by hand.

### Key loss and key leak

- **Key loss.** Without the private key, you cannot sign updates, and
  installed apps refuse any update with another key. Restore the key from the
  offline backup with `generate_keys -f <file>`. If no backup exists, create
  a new key pair, ship a release with the new public key, and tell users to
  install it by hand from the DMG.
- **Key leak.** An attacker with the key and control of the feed can sign
  updates that every user installs, and there is no revocation. Immediately
  create a new key pair, ship a release with the new public key, and announce
  the leak with instructions to install that release by hand from the DMG.
  Then remove the old key from the Keychain.

Sparkle accepts an update with a new public key only when the Apple code
signatures of the old and new app match. Ad-hoc builds have no stable
signing identity, so plan for a manual install after any key change.

## Infrastructure Dependencies

| Dependency | Type | Version / requirement | Installation |
| --- | --- | --- | --- |
| macOS | Host OS | 14.0 or later, Apple Silicon (meet tart's own host requirements) | — |
| `tart` | CLI executable | `2.0.0` or later (`TartVersion.minimumSupported`) | Bundled in the app. A separate install is optional: `brew install cirruslabs/cli/tart` |
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

Packaged builds include tart at `Contents/Helpers/tart.app` (see [Bundled
tart](#bundled-tart)). New users get the bundled tart by default. A separate
tart is optional: a user can select it with **Path** in Settings → General →
**Tart**. On startup the app probes `tart --version` and shows a banner with
remediation commands when the selected tart is unusable:

- Missing: `brew install cirruslabs/cli/tart`
- Outdated: `brew upgrade cirruslabs/cli/tart`

With **Path**, the binary is located in this order:

1. The custom path from **Choose…** in Settings
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

Sparkle owns its own keys in the same domain: `SUEnableAutomaticChecks` (the
**Check for updates automatically** setting; it overrides the `Info.plist`
default), `SULastCheckTime`, and `SUSkippedVersion`. Tart Manager adds no
update preference keys of its own.

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
endpoints. It talks to two external systems: OCI container registries,
through the `tart` CLI, and GitHub Releases, for in-app updates.

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

The tart CLI starts that traffic. The app itself connects only to GitHub for
updates: `github.com` and the release-asset download host it redirects to
(`release-assets.githubusercontent.com` or `objects.githubusercontent.com`).
Update checks send no system profile; GitHub receives the IP address and the
user agent.

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
  `deleteVM`, `rename`, `replaceDisk`, `registries`, `sharedFolders`, `icon`,
  `clipboard`, `updates`.
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
log stream --predicate 'subsystem == "app.TartManager" AND category == "updates"'
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
