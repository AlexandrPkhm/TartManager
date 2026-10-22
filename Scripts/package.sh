#!/usr/bin/env bash
#
# package.sh — build Tart Manager and package it into a distributable DMG.
#
# Stages:
#   0. Tart check       offer a newer openai/tart release; bump the pin only
#                       after the maintainer answers y (--skip-tart-check skips)
#   1. Release build    swift build -c release
#   2. Bundled tart     download the tart release pinned in Scripts/tart-pin.env,
#                       check its SHA-256, signature, and LICENSE
#   3. Bundle assembly  assemble "Tart Manager.app" (binary, icon, Info.plist,
#                       Sparkle.framework, the unchanged tart.app and its license)
#   4. Code signing     ad-hoc by default; --sign for a Developer ID identity.
#                       Nested Sparkle code is signed inside-out, never --deep.
#                       tart.app keeps its own Developer ID signature.
#   5. DMG creation     hdiutil (app + /Applications symlink)
#   6. Notarization     optional, via --notarize (Developer ID signing required)
#   7. Appcast          optional, via --appcast: the EdDSA-signed update feed
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

# Bundled tart. The pin file is the trust anchor for the download; the
# signing team must equal BundledTartVerifier.expectedTeamIdentifier. See
# Docs/DEPLOYMENT.md → Bundled tart.
TART_PIN_FILE="$ROOT/Scripts/tart-pin.env"
TART_LICENSE_REF="$ROOT/Scripts/tart-LICENSE.txt"
TART_REPO="openai/tart"
TART_TEAM_ID="9M2P8L4D89"
TART_CACHE_DIR="$ROOT/.build/tart-cache"
TART_VERSION=""
TART_SHA256=""
TART_EXTRACTED=""
SKIP_TART_CHECK=false
CHECK_TART_ONLY=false

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
      --skip-tart-check   Do not look for a newer tart release (offline builds).
      --check-tart        Run only the tart release check, then exit.
      --tart-pin-file PATH
                          Read the bundled tart pin from PATH
                          (default: Scripts/tart-pin.env).
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
            --skip-tart-check)
                SKIP_TART_CHECK=true
                shift
                ;;
            --check-tart)
                CHECK_TART_ONLY=true
                shift
                ;;
            --tart-pin-file)
                [[ $# -ge 2 ]] || fail "$1 requires a value"
                TART_PIN_FILE="$2"
                shift 2
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
    for tool in hdiutil codesign plutil swift xcrun install_name_tool ditto \
            gh shasum tar spctl; do
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
        # Release tags are `vX.Y.Z`; the bundle version is `X.Y.Z`.
        VERSION="${VERSION#v}"
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
    embed_tart "$bundle"

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

# Reads TART_VERSION and TART_SHA256 from TART_PIN_FILE.
load_tart_pin() {
    [[ -f "$TART_PIN_FILE" ]] || fail "tart pin file not found: $TART_PIN_FILE"
    TART_VERSION=""
    TART_SHA256=""
    # shellcheck source=/dev/null
    source "$TART_PIN_FILE"
    [[ -n "$TART_VERSION" && -n "$TART_SHA256" ]] || \
        fail "$TART_PIN_FILE must set TART_VERSION and TART_SHA256"
    [[ "$TART_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
        fail "TART_VERSION must look like X.Y.Z, got: $TART_VERSION"
    [[ "$TART_SHA256" =~ ^[0-9a-f]{64}$ ]] || \
        fail "TART_SHA256 must be 64 lowercase hex digits"
}

sha256_of() {
    shasum -a 256 "$1" | awk '{ print $1 }'
}

# Prints the SHA-256 that the release checksums file lists for tart.tar.gz.
checksum_from_release() {
    local checksums="$1"
    awk '$2 == "tart.tar.gz" || $2 == "*tart.tar.gz" { print $1; exit }' "$checksums"
}

# Downloads tart.tar.gz and the checksums file of tart VERSION into a new,
# empty directory and prints that directory.
download_tart_assets() {
    local version="$1"
    local dir
    dir="$(mktemp -d "$STAGING_DIR/tart-download.XXXXXX")"
    gh release download "$version" --repo "$TART_REPO" --dir "$dir" \
        --pattern tart.tar.gz --pattern "tart_${version}_checksums.txt" >&2 || \
        fail "could not download tart $version from $TART_REPO"
    echo "$dir"
}

# Fetches tart VERSION (from the cache or GitHub), checks it against SHA256 and
# the release checksums file, and extracts it into DEST_DIR, which must be new
# and empty. The archive holds tart.app/ and LICENSE at its root.
fetch_tart_archive() {
    local version="$1" sha256="$2" dest="$3"
    local cache="$TART_CACHE_DIR/$version"
    local archive="$cache/tart.tar.gz"
    local checksums="$cache/tart_${version}_checksums.txt"

    if [[ -f "$archive" && "$(sha256_of "$archive")" != "$sha256" ]]; then
        echo "==> Cached tart $version does not match the pin; downloading again"
        rm -f "$archive" "$checksums"
    fi
    if [[ ! -f "$archive" || ! -f "$checksums" ]]; then
        echo "==> Downloading tart $version from $TART_REPO"
        local download
        download="$(download_tart_assets "$version")"
        [[ "$(sha256_of "$download/tart.tar.gz")" == "$sha256" ]] || \
            fail "tart $version SHA-256 does not match $TART_PIN_FILE"
        mkdir -p "$cache"
        mv "$download/tart.tar.gz" "$archive"
        mv "$download/tart_${version}_checksums.txt" "$checksums"
    else
        echo "==> Using cached tart $version"
    fi

    [[ "$(sha256_of "$archive")" == "$sha256" ]] || \
        fail "tart $version SHA-256 does not match $TART_PIN_FILE"
    [[ "$(checksum_from_release "$checksums")" == "$sha256" ]] || \
        fail "tart $version SHA-256 does not match the release checksums file"

    [[ -d "$dest" && -z "$(ls -A "$dest")" ]] || \
        fail "extraction folder must be new and empty: $dest"
    tar -xzf "$archive" -C "$dest" || fail "could not extract tart $version"
    [[ -x "$dest/tart.app/Contents/MacOS/tart" ]] || \
        fail "tart $version archive has no tart.app/Contents/MacOS/tart"
    [[ -f "$dest/LICENSE" ]] || fail "tart $version archive has no LICENSE"
}

# Prints the tag of the latest openai/tart release, or nothing on failure.
latest_tart_tag() {
    gh release view --repo "$TART_REPO" --json tagName --jq .tagName 2>/dev/null || true
}

# True when version A is higher than version B; both are X.Y.Z.
version_newer() {
    local a="$1" b="$2"
    local a1 a2 a3 b1 b2 b3
    IFS=. read -r a1 a2 a3 <<<"$a"
    IFS=. read -r b1 b2 b3 <<<"$b"
    (( 10#$a1 != 10#$b1 )) && { (( 10#$a1 > 10#$b1 )); return; }
    (( 10#$a2 != 10#$b2 )) && { (( 10#$a2 > 10#$b2 )); return; }
    (( 10#$a3 > 10#$b3 ))
}

# Asks QUESTION on the terminal. True only for an answer of y or Y; false
# without a terminal, so a release build never bumps without an answer.
confirm() {
    local question="$1" answer=""
    [[ -t 0 ]] || return 1
    read -r -p "$question" answer || return 1
    [[ "$answer" == "y" || "$answer" == "Y" ]]
}

# Offers the latest openai/tart release when it is newer than the pin.
check_tart_release() {
    local latest
    latest="$(latest_tart_tag)"
    if [[ ! "$latest" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "warning: could not read the latest $TART_REPO release; skipping the tart check" >&2
        return
    fi
    echo "==> Bundled tart: pinned $TART_VERSION, latest $latest"
    if ! version_newer "$latest" "$TART_VERSION"; then
        echo "==> Bundled tart $TART_VERSION is current"
        return
    fi
    echo "    https://github.com/$TART_REPO/releases/tag/$latest"
    if confirm "Bump bundled tart to $latest? [y/N] "; then
        bump_tart_pin "$latest"
    else
        echo "==> Keeping bundled tart $TART_VERSION; $latest is available"
    fi
}

# Downloads and verifies tart VERSION, then rewrites the pin (and the license
# reference after a second y) only when every check passed. Never commits.
bump_tart_pin() {
    local version="$1"
    local download extracted expected
    download="$(download_tart_assets "$version")"
    expected="$(checksum_from_release "$download/tart_${version}_checksums.txt")"
    [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || \
        fail "tart $version checksums file has no SHA-256 for tart.tar.gz"
    [[ "$(sha256_of "$download/tart.tar.gz")" == "$expected" ]] || \
        fail "tart $version archive does not match its release checksums file"
    mkdir -p "$TART_CACHE_DIR/$version"
    mv "$download/tart.tar.gz" "$download/tart_${version}_checksums.txt" \
        "$TART_CACHE_DIR/$version/"

    extracted="$(mktemp -d "$STAGING_DIR/tart-extract.XXXXXX")"
    fetch_tart_archive "$version" "$expected" "$extracted"
    verify_tart_app "$extracted/tart.app" "$version"

    local files="$TART_PIN_FILE"
    if ! cmp -s "$extracted/LICENSE" "$TART_LICENSE_REF"; then
        diff -u "$TART_LICENSE_REF" "$extracted/LICENSE" || true
        if ! confirm "The tart license text changed. Accept the new license? [y/N] "; then
            echo "==> Keeping bundled tart $TART_VERSION; $version is available"
            return
        fi
        cp "$extracted/LICENSE" "$TART_LICENSE_REF"
        files="$files $TART_LICENSE_REF"
    fi

    local comment
    comment="$(grep '^#' "$TART_PIN_FILE" || true)"
    {
        [[ -z "$comment" ]] || printf '%s\n' "$comment"
        printf 'TART_VERSION=%s\n' "$version"
        printf 'TART_SHA256=%s\n' "$expected"
    } > "$TART_PIN_FILE.tmp"
    mv "$TART_PIN_FILE.tmp" "$TART_PIN_FILE"

    echo "==> Bumped bundled tart to $version"
    echo "    Commit these files on their own, with a CHANGELOG entry: $files"
    echo "    Suggested subject: chore: bump bundled tart to $version"
}

# Checks that APP is the genuine, unchanged tart VERSION: a valid signature by
# the Cirrus Labs team, accepted by Gatekeeper, with its provisioning profile.
verify_tart_app() {
    local app="$1" version="$2"
    echo "==> Verifying tart.app $version"
    codesign --verify --strict --verbose=2 "$app" || \
        fail "tart.app signature verification failed"
    codesign -dv "$app" 2>&1 | grep -qx "TeamIdentifier=$TART_TEAM_ID" || \
        fail "tart.app is not signed by team $TART_TEAM_ID"
    spctl --assess --type execute "$app" || \
        fail "Gatekeeper rejects tart.app"
    [[ "$("$app/Contents/MacOS/tart" --version)" == "$version" ]] || \
        fail "tart.app does not report version $version"
    [[ -f "$app/Contents/embedded.provisionprofile" ]] || \
        fail "tart.app has no embedded.provisionprofile"
}

# Fetches and verifies the pinned tart into a new staging folder, before the
# bundle is assembled, and records that folder in TART_EXTRACTED.
prepare_tart() {
    TART_EXTRACTED="$(mktemp -d "$STAGING_DIR/tart-extract.XXXXXX")"
    fetch_tart_archive "$TART_VERSION" "$TART_SHA256" "$TART_EXTRACTED"
    verify_tart_app "$TART_EXTRACTED/tart.app" "$TART_VERSION"
    cmp -s "$TART_EXTRACTED/LICENSE" "$TART_LICENSE_REF" || \
        fail "tart $TART_VERSION LICENSE differs from $TART_LICENSE_REF"
}

# Embeds the verified tart.app unchanged, with its license. The copy keeps the
# upstream signature: nothing here or in sign_app re-signs it.
embed_tart() {
    local bundle="$1"
    [[ -n "$TART_EXTRACTED" ]] || fail "embed_tart needs prepare_tart first"
    mkdir -p "$bundle/Contents/Helpers"
    ditto "$TART_EXTRACTED/tart.app" "$bundle/Contents/Helpers/tart.app"
    cp "$TART_LICENSE_REF" "$bundle/Contents/Resources/tart-LICENSE.txt"
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

# Signs nested code inside-out, then the bundle. Never use --deep, and never
# sign Contents/Helpers/tart.app: it keeps its Developer ID signature.
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

    # Prove that signing the bundle left the nested tart.app intact.
    local tart_app="$bundle/Contents/Helpers/tart.app"
    codesign --verify --strict --verbose=2 "$tart_app" || \
        fail "code signature verification failed for $tart_app"
    codesign -dv "$tart_app" 2>&1 | grep -qx "TeamIdentifier=$TART_TEAM_ID" || \
        fail "signing changed the team of $tart_app"
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
    # --check-tart builds nothing, so it needs no version.
    [[ "$CHECK_TART_ONLY" == true ]] || resolve_version
    require_tools
    load_tart_pin

    # Global (not `local`) so the EXIT trap below can still see it: `local`
    # variables of a function are out of scope once that function returns.
    STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tartmanager-package.XXXXXX")"
    trap '[[ -z "${STAGING_DIR:-}" ]] || rm -rf "$STAGING_DIR"' EXIT

    if [[ "$SKIP_TART_CHECK" == true ]]; then
        echo "==> Skipped the tart release check (--skip-tart-check)"
    else
        check_tart_release
        load_tart_pin
    fi
    [[ "$CHECK_TART_ONLY" == true ]] && exit 0

    build_release
    prepare_tart

    local bundle="$STAGING_DIR/$APP_BUNDLE"
    assemble_app "$bundle"
    sign_app "$bundle"
    local dmg_path
    dmg_path="$(create_dmg "$STAGING_DIR")"
    notarize_dmg "$dmg_path"
    write_appcast "$dmg_path"

    local size_mb
    size_mb="$(awk -v bytes="$(stat -f %z "$dmg_path")" \
        'BEGIN { printf "%.1f", bytes / 1048576 }')"
    echo "==> Done: $dmg_path ($size_mb MB)"
}

main "$@"
