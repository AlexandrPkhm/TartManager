# Changelog

All notable changes to this project will be documented in this file.

The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Added

- Added the **Tart** panel to Settings → General: choose the bundled tart or
  a tart on this Mac (detected automatically or chosen with **Choose…**),
  and see the active tart's version, source, and path.
- Added a one-time question that asks which tart to use when both the
  bundled and the installed tart work, and a warning when the selected tart
  is older than the other one.
- Added a **Use bundled tart** or **Use installed tart** button to the tart
  banner when the other tart works.
- Added the active tart's version, source, and path to copied error reports
  and to Settings → About.
- Added tart 2.41.1 inside Tart Manager, so you do not need Homebrew or a
  separate tart. The bundled tart is the default for new users.
- Added an **Acknowledgements** panel to Settings → About with the tart
  license (**View License**) and a link to tart on GitHub.

### Changed

- Changed the tart banner to name the failure of the selected tart: missing,
  damaged, cannot run, or outdated.

### Removed

- Removed the **Detected tart** row from Settings → Storage; Settings →
  General → **Tart** shows it now.

## 1.2.0 - 2026-10-20

### Added

- Added a **Jobs** section at the bottom of the main-window sidebar that shows
  the progress of each running job, cancels clone, import, export, create, and
  cache-cleanup jobs, and keeps failed jobs with a link to the error details.
- Added in-app updates: Tart Manager checks for a new version once a day,
  shows an **Update Available** button in the title bar and an
  **Update available…** item in the menu-bar menu, and installs a verified
  update after running jobs finish.
- Added the **About** tab in Settings, with the version, the update status,
  a **Check for Updates** button, and links to GitHub and the documentation.
- Added the **Check for updates automatically** setting to Settings →
  General.

### Changed

- Changed **Tart Manager → About Tart Manager** to open Settings on the
  **About** tab.
- Changed `CFBundleVersion` to match the release version instead of `1`.

### Removed

- Removed the About sheet. The README now describes running, stopping,
  suspending, replacing a disk, memory warnings, and pruning caches.

## 1.1.0 - 2026-10-20

### Changed

- Changed the VM storage unavailable screen to show the cause, the storage
  path with a copy button, and a note that the app checks storage again every
  30 seconds.
- Changed inventory polling to pause while VM storage is unavailable, so the
  app no longer runs `tart list` every 3 seconds for a missing volume.

### Fixed

- Fixed the main-window controls (close, minimize, zoom) so they align with
  the top bar and stay in position while the window resizes.
- Fixed the truncated "Choose Another Folder…" button on the VM storage
  unavailable screen.

## 1.0.0 - 2026-10-13

### Added

- Added the initial 1.0.0 release baseline.
