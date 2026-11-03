#!/usr/bin/env bash
#
# update-registry-catalog.sh — scan ghcr.io/cirruslabs and update the default
# registry image list.
#
# GHCR refuses anonymous catalog requests and the GitHub packages API needs a
# read:packages token. Thus this script reads the public package pages to find
# names, then asks GHCR to confirm that each image has the "latest" tag.
#
# The package pages are not a stable API. Do not use them in the app. If the
# pages change, this script stops with an error and does not change the list.
#
# Usage: Scripts/update-registry-catalog.sh [--catalog <path>]
#
# Exit status: 0 when the list is current or updated, 1 on a scan failure.
# See Docs/DEVELOPMENT.md → Updating the default registry image list.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CATALOG="$ROOT/Catalog/default-registry-images.json"

ORG="cirruslabs"
PACKAGES_URL="https://github.com/orgs/$ORG/packages?ecosystem=container"
MAX_PAGES=20

# VM images only. The organization also publishes services and CI tools.
IMAGE_PATTERN='^(macos-[a-z]+(-[a-z]+)*-(base|vanilla|xcode)|debian|fedora|ubuntu)$'

die() {
    echo "error: $*" >&2
    exit 1
}

fetch() {
    curl --silent --show-error --location --max-time 30 --retry 3 "$@"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --catalog)
            [ $# -ge 2 ] || die "--catalog needs a path"
            CATALOG="$2"
            shift 2
            ;;
        *)
            die "unknown argument: $1"
            ;;
    esac
done

[ -f "$CATALOG" ] || die "catalog not found: $CATALOG"

schema="$(jq -r '.schemaVersion' "$CATALOG")"
[ "$schema" = "1" ] || die "unsupported schemaVersion: $schema"

# Read pages until a page has no packages.
packages=""
page=1
while :; do
    [ "$page" -le "$MAX_PAGES" ] || die "more than $MAX_PAGES package pages"
    names="$(fetch --fail "$PACKAGES_URL&page=$page" \
        | grep -oE '/packages/container/package/[a-z0-9._-]+' \
        | sed 's#.*/##' | sort -u || true)"
    [ -n "$names" ] || break
    packages="$packages$names"$'\n'
    page=$((page + 1))
done
[ -n "$packages" ] || die "no packages found; the page format may have changed"

candidates="$(printf '%s' "$packages" | sort -u | grep -E "$IMAGE_PATTERN" || true)"
[ -n "$candidates" ] || die "no VM images found; the page format may have changed"

# Keep only images that have the "latest" tag.
found=""
for image in $candidates; do
    response="$(fetch --write-out '\n%{http_code}' \
        "https://ghcr.io/token?scope=repository:$ORG/$image:pull")"
    status="${response##*$'\n'}"
    if [ "$status" = "403" ]; then
        echo "warning: skipped $image: GHCR denied anonymous access" >&2
        continue
    fi
    [ "$status" = "200" ] || die "GHCR token request for $image returned $status"
    token="$(printf '%s' "${response%$'\n'*}" | jq -r '.token')"

    tags="$(fetch --fail -H "Authorization: Bearer $token" \
        "https://ghcr.io/v2/$ORG/$image/tags/list?n=5000")"
    if printf '%s' "$tags" | jq -e '(.tags // []) | index("latest")' >/dev/null; then
        found="$found$image"$'\n'
    else
        echo "warning: skipped $image: no latest tag" >&2
    fi
done

# A large drop means a bad scan, not a real removal. Stop and keep the list.
current_count="$(jq '.images | length' "$CATALOG")"
found_count="$(printf '%s' "$found" | grep -c . || true)"
[ "$found_count" -gt 0 ] || die "no usable images found"
[ $((found_count * 2)) -ge "$current_count" ] \
    || die "found $found_count images, but the list has $current_count"

# Keep the order and labels of known images, so the diff shows only real
# changes. New macOS images go first because a new image is usually the newest.
updated="$(mktemp "$CATALOG.XXXXXX")"
trap 'rm -f "$updated"' EXIT
printf '%s' "$found" | jq -R -s --slurpfile current "$CATALOG" --arg org "$ORG" '
    def reference: "ghcr.io/\($org)/\(.):latest";
    def titled: split("-") | map((.[0:1] | ascii_upcase) + .[1:]) | join(" ");
    def image_label:
        if startswith("macos-") then
            (ltrimstr("macos-") | split("-")) as $parts
            | "macOS \($parts[:-1] | join("-") | titled) · \($parts[-1])"
        else titled end;
    (split("\n") | map(select(length > 0))) as $found
    | ($found | map(reference)) as $references
    | ($current[0].images | map(.reference)) as $known
    | ($current[0].images | map(select(.reference as $r | $references | index($r)))) as $kept
    | ($found | map(select(reference as $r | $known | index($r) | not))
        | map({label: image_label, reference: reference})) as $new
    | {
        schemaVersion: 1,
        images: (($new | map(select(.reference | contains("/macos-"))))
            + $kept
            + ($new | map(select(.reference | contains("/macos-") | not))))
      }
' > "$updated"

chmod 644 "$updated"
mv "$updated" "$CATALOG"
trap - EXIT
echo "Scan complete: $found_count images in $CATALOG"
