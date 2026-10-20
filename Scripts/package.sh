#!/usr/bin/env bash
#
# package.sh — build Tart Manager and package it into a distributable DMG.
#
# Stages:
#   1. Release build    swift build -c release
#   2. Bundle assembly  assemble "Tart Manager.app" (binary, icon, Info.plist,
#                       Sparkle.framework)
#   3. Code signing     ad-hoc by default; --sign for a Developer ID identity.
#                       Nested Sparkle code is signed inside-out, never --deep.
#   4. DMG creation     hdiutil (app + /Applications symlink)
#   5. Notarization     optional, via --notarize (Developer ID signing required)
#   6. Appcast          optional, via --appcast: the EdDSA-signed update feed
#                       and Markdown release notes from CHANGELOG.md
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

# In-app updates (Sparkle). The public key is the trust anchor for every
# update; its private half stays in the maintainer's login Keychain. See
# Docs/DEPLOYMENT.md → In-App Updates.
SPARKLE_PUBLIC_ED_KEY="fji7wp6SDYVkEnj4+Fv8kN6J+6NrtSAr1w10K1zHzdA="
FEED_URL="https://github.com/AlexandrPkhm/TartManager/releases/latest/download/appcast.xml"
DOWNLOAD_URL_PREFIX_BASE="https://github.com/AlexandrPkhm/TartManager/releases/download"
PROJECT_URL="https://github.com/AlexandrPkhm/TartManager"
SPARKLE_BIN="$ROOT/.build/artifacts/sparkle/Sparkle/bin"

VERSION=""
SIGN_IDENTITY=""
NOTARIZE=false
APPCAST=false
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
      --appcast           Write the signed update feed to DIR/updates/:
                          appcast.xml, the DMG, and release notes from the
                          CHANGELOG.md section for VERSION. Signs with the
                          EdDSA key in the login Keychain.
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
            --appcast)
                APPCAST=true
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
    for tool in hdiutil codesign plutil swift xcrun install_name_tool ditto; do
        command -v "$tool" >/dev/null 2>&1 || fail "required tool not found: $tool"
    done
    if [[ "$SKIP_BUILD" != true ]]; then
        command -v swift >/dev/null 2>&1 || fail "required tool not found: swift"
    fi
    if [[ "$NOTARIZE" == true ]]; then
        command -v xcrun >/dev/null 2>&1 || fail "required tool not found: xcrun"
    fi
    if [[ "$APPCAST" == true ]]; then
        [[ -x "$SPARKLE_BIN/generate_appcast" ]] || \
            fail "generate_appcast not found at $SPARKLE_BIN — run swift build first"
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

    mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources" "$bundle/Contents/Frameworks"
    cp "$BINARY_PATH" "$bundle/Contents/MacOS/$EXECUTABLE"
    embed_sparkle "$bundle"

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
    <key>CFBundleVersion</key>          <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>   <string>$MIN_MACOS</string>
    <key>NSHighResolutionCapable</key>  <true/>
    <key>SUFeedURL</key>                <string>$FEED_URL</string>
    <key>SUPublicEDKey</key>            <string>$SPARKLE_PUBLIC_ED_KEY</string>
    <key>SUEnableAutomaticChecks</key>  <true/>
    <key>SUEnableSystemProfiling</key>  <false/>
    <key>SUScheduledCheckInterval</key> <integer>86400</integer>
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

# Copies Sparkle.framework from the SwiftPM release products into the bundle.
# The XPC services are only for sandboxed apps; Tart Manager is not sandboxed.
# The release binary has no rpath to Contents/Frameworks, so one is added.
embed_sparkle() {
    local bundle="$1"
    local source
    source="$(dirname "$BINARY_PATH")/Sparkle.framework"
    [[ -d "$source" ]] || fail "Sparkle.framework not found at $source"

    local framework="$bundle/Contents/Frameworks/Sparkle.framework"
    ditto "$source" "$framework"
    rm -rf "$framework/Versions/B/XPCServices" "$framework/XPCServices"
    install_name_tool -add_rpath "@executable_path/../Frameworks" \
        "$bundle/Contents/MacOS/$EXECUTABLE"
}

# Signs one path. Ad-hoc signing never uses the hardened runtime: Library
# Validation would then refuse the ad-hoc Sparkle.framework.
sign_path() {
    local path="$1"
    if [[ -n "$SIGN_IDENTITY" ]]; then
        codesign --force --options runtime --timestamp \
            --sign "$SIGN_IDENTITY" "$path"
    else
        codesign --force --sign - "$path"
    fi
}

# Signs nested code inside-out, then the bundle. Never use --deep.
sign_app() {
    local bundle="$1"
    local framework="$bundle/Contents/Frameworks/Sparkle.framework"
    if [[ -n "$SIGN_IDENTITY" ]]; then
        echo "==> Signing with Developer ID: $SIGN_IDENTITY"
    else
        echo "==> Signing ad-hoc (this Mac only)"
    fi
    sign_path "$framework/Versions/B/Autoupdate"
    sign_path "$framework/Versions/B/Updater.app"
    sign_path "$framework"
    sign_path "$bundle"
    codesign --verify --strict --verbose=2 "$bundle" || \
        fail "code signature verification failed for $bundle"
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

# Prints the body of the CHANGELOG.md section "## VERSION ..." up to the next
# "## " heading, without the heading itself.
changelog_section() {
    awk -v version="$VERSION" '
        /^## / {
            if (found) exit
            if ($2 == version) { found = 1; next }
        }
        found { print }
    ' "$ROOT/CHANGELOG.md"
}

write_appcast() {
    local dmg_path="$1"
    if [[ "$APPCAST" != true ]]; then
        return
    fi
    local updates_dir="${OUTPUT_DIR:?}/updates"
    echo "==> Writing signed appcast to $updates_dir"

    local notes
    notes="$(changelog_section)"
    [[ -n "${notes//[[:space:]]/}" ]] || \
        fail "CHANGELOG.md has no non-empty '## $VERSION' section"

    # One release per feed: start from an empty folder every time.
    rm -rf "$updates_dir"
    mkdir -p "$updates_dir"
    cp "$dmg_path" "$updates_dir/"
    printf '%s\n' "$notes" > "$updates_dir/TartManager-$VERSION.md"

    "$SPARKLE_BIN/generate_appcast" \
        --download-url-prefix "$DOWNLOAD_URL_PREFIX_BASE/v$VERSION/" \
        --embed-release-notes \
        --link "$PROJECT_URL" \
        "$updates_dir"

    [[ -f "$updates_dir/appcast.xml" ]] || fail "generate_appcast wrote no appcast.xml"
    grep -q 'sparkle:edSignature' "$updates_dir/appcast.xml" || \
        fail "appcast.xml has no sparkle:edSignature"
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
    write_appcast "$dmg_path"

    echo "==> Done: $dmg_path"
}

main "$@"
