#!/usr/bin/env bash
#
# package.sh — build Tart Manager and package it into a distributable DMG.
#
# Stages:
#   1. Release build    swift build -c release
#   2. Bundle assembly  assemble "Tart Manager.app" (binary, icon, Info.plist)
#   3. Code signing     ad-hoc by default; --sign for a Developer ID identity
#   4. DMG creation     hdiutil (app + /Applications symlink)
#   5. Notarization     optional, via --notarize (Developer ID signing required)
#
# See Docs/DEPLOYMENT.md → Packaging for the manual, step-by-step equivalent and
# the rationale for each decision (bundle ID, icon source, notarization).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BINARY_PATH=""
ICON_SOURCE="$ROOT/Assets/AppIcon.icon"

APP_NAME="Tart Manager"
APP_BUNDLE="$APP_NAME.app"
EXECUTABLE="TartManager"
# Must stay "TartManager" (not reverse-DNS): it is the UserDefaults domain
# the bare `swift run` binary already uses. See Docs/DEPLOYMENT.md → Packaging.
BUNDLE_ID="TartManager"
MIN_MACOS="14.0"
FALLBACK_VERSION="1.0.0"

VERSION=""
SIGN_IDENTITY=""
NOTARIZE=false
SKIP_BUILD=false
OUTPUT_DIR="$ROOT/dist"

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -v, --version VERSION   Version to stamp into the bundle and DMG name
                          (default: latest git tag, or $FALLBACK_VERSION if none).
      --sign IDENTITY     Sign with a Developer ID identity (e.g.
                          "Developer ID Application: Jane Doe (TEAM123)").
                          Default is ad-hoc signing, which only works on the
                          machine that built it.
      --notarize          Notarize and staple the finished DMG. Requires
                          --sign and the NOTARY_PROFILE environment variable.
      --skip-build        Reuse the existing release binary instead of
                          running swift build -c release.
  -o, --output DIR        Output directory for the DMG (default: dist/).
  -h, --help              Show this help.
EOF
}

fail() {
    echo "error: $*" >&2
    exit 1
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--version)
                [[ $# -ge 2 ]] || fail "$1 requires a value"
                VERSION="$2"
                shift 2
                ;;
            --sign)
                [[ $# -ge 2 ]] || fail "$1 requires a value"
                SIGN_IDENTITY="$2"
                shift 2
                ;;
            --notarize)
                NOTARIZE=true
                shift
                ;;
            --skip-build)
                SKIP_BUILD=true
                shift
                ;;
            -o|--output)
                [[ $# -ge 2 ]] || fail "$1 requires a value"
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                fail "unknown argument: $1"
                ;;
        esac
    done
}

require_tools() {
    local tool
    for tool in hdiutil codesign plutil swift xcrun; do
        command -v "$tool" >/dev/null 2>&1 || fail "required tool not found: $tool"
    done
    if [[ "$SKIP_BUILD" != true ]]; then
        command -v swift >/dev/null 2>&1 || fail "required tool not found: swift"
    fi
    if [[ "$NOTARIZE" == true ]]; then
        command -v xcrun >/dev/null 2>&1 || fail "required tool not found: xcrun"
    fi
}

resolve_version() {
    if [[ -z "$VERSION" ]]; then
        VERSION="$(git -C "$ROOT" describe --tags --abbrev=0 2>/dev/null || true)"
        [[ -z "$VERSION" ]] && VERSION="$FALLBACK_VERSION"
        echo "==> No --version given; using $VERSION"
    fi
    [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
        fail "version must look like X.Y.Z, got: $VERSION"
}

build_release() {
    if [[ "$SKIP_BUILD" == true ]]; then
        echo "==> Skipping build (--skip-build)"
    else
        echo "==> Building release configuration"
        (cd "$ROOT" && swift build -c release)
    fi
    BINARY_PATH="$(cd "$ROOT" && swift build -c release --show-bin-path)/TartManager"
    [[ -x "$BINARY_PATH" ]] || \
        fail "binary not found at $BINARY_PATH — run without --skip-build"
    [[ -f "$ICON_SOURCE/icon.json" ]] || \
        fail "Icon Composer source not found at $ICON_SOURCE"
}

assemble_app() {
    local bundle="$1"
    echo "==> Assembling $APP_BUNDLE"

    mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
    cp "$BINARY_PATH" "$bundle/Contents/MacOS/$EXECUTABLE"

    cat > "$bundle/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>       <string>$EXECUTABLE</string>
    <key>CFBundleIdentifier</key>       <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>             <string>TartManager</string>
    <key>CFBundleDisplayName</key>      <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>      <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>$VERSION</string>
    <key>CFBundleVersion</key>          <string>1</string>
    <key>LSMinimumSystemVersion</key>   <string>$MIN_MACOS</string>
    <key>NSHighResolutionCapable</key>  <true/>
</dict>
</plist>
PLIST
    # Compile the layered icon so macOS can render its native appearance
    # variants. A standalone ICNS loses those layers and system treatments.
    local icon_plist="$(dirname "$bundle")/icon-info.plist"
    xcrun actool "$ICON_SOURCE" \
        --compile "$bundle/Contents/Resources" \
        --output-format human-readable-text --notices --warnings --errors \
        --output-partial-info-plist "$icon_plist" \
        --app-icon AppIcon --include-all-app-icons \
        --enable-on-demand-resources NO --development-region en \
        --target-device mac --minimum-deployment-target "$MIN_MACOS" \
        --platform macosx
    /usr/libexec/PlistBuddy -c "Merge '$icon_plist'" "$bundle/Contents/Info.plist"
    [[ -f "$bundle/Contents/Resources/Assets.car" ]] || \
        fail "icon compilation did not produce Assets.car"
    plutil -lint "$bundle/Contents/Info.plist" >/dev/null || \
        fail "generated Info.plist failed validation"
}

sign_app() {
    local bundle="$1"
    if [[ -n "$SIGN_IDENTITY" ]]; then
        echo "==> Signing with Developer ID: $SIGN_IDENTITY"
        codesign --force --options runtime --timestamp \
            --sign "$SIGN_IDENTITY" "$bundle"
    else
        echo "==> Signing ad-hoc (this Mac only)"
        codesign --force --sign - "$bundle"
    fi
}

create_dmg() {
    local staging="$1"
    local dmg_root="$staging/dmg-root"
    echo "==> Creating DMG" >&2

    mkdir -p "$dmg_root"
    cp -R "$staging/$APP_BUNDLE" "$dmg_root/"
    ln -s /Applications "$dmg_root/Applications"

    mkdir -p "$OUTPUT_DIR"
    local dmg_path="$OUTPUT_DIR/TartManager-$VERSION.dmg"
    hdiutil create -volname "$APP_NAME" -srcfolder "$dmg_root" \
        -ov -format UDZO "$dmg_path" >/dev/null
    echo "$dmg_path"
}

notarize_dmg() {
    local dmg_path="$1"
    if [[ "$NOTARIZE" != true ]]; then
        return
    fi
    [[ -n "$SIGN_IDENTITY" ]] || fail "--notarize requires --sign"
    [[ -n "${NOTARY_PROFILE:-}" ]] || fail "--notarize requires NOTARY_PROFILE"

    echo "==> Submitting DMG for notarization"
    xcrun notarytool submit "$dmg_path" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait
    echo "==> Stapling notarization ticket"
    xcrun stapler staple "$dmg_path"
}

main() {
    parse_args "$@"
    resolve_version
    require_tools
    build_release

    # Global (not `local`) so the EXIT trap below can still see it: `local`
    # variables of a function are out of scope once that function returns.
    STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tartmanager-package.XXXXXX")"
    trap '[[ -z "${STAGING_DIR:-}" ]] || rm -rf "$STAGING_DIR"' EXIT

    local bundle="$STAGING_DIR/$APP_BUNDLE"
    assemble_app "$bundle"
    sign_app "$bundle"
    local dmg_path
    dmg_path="$(create_dmg "$STAGING_DIR")"
    notarize_dmg "$dmg_path"

    echo "==> Done: $dmg_path"
}

main "$@"
