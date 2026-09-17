# Tart Manager

A native macOS app that provides a Parallels-style control center for
[tart](https://github.com/cirruslabs/tart) virtual machines: list your VMs,
run, stop, suspend, edit resources, create VMs from OCI images, and manage
snapshots — without a terminal.

Early in development. Targets macOS 14+, wraps the locally installed
`tart` CLI (which must be installed separately).

## Development

Open the package root and run:

    swift build
    swift test
    swift run    # launches the app

CI runs build + tests on every pull request.

## License

MIT — see LICENSE.
