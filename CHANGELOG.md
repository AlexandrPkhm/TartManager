# Changelog

All notable changes to this project will be documented in this file.

The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

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
