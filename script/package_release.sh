#!/usr/bin/env bash
set -euo pipefail

APP_VERSION="${1:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SIGNING_IDENTITY="${MINUTE_SIGNING_IDENTITY:--}"
NOTARY_PROFILE="${MINUTE_NOTARY_PROFILE:-}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/minute.app"
ARCHIVE="$ROOT_DIR/dist/minute-$APP_VERSION.zip"

BUILD_CONFIGURATION=release BUILD_UNIVERSAL=1 APP_VERSION="$APP_VERSION" BUILD_NUMBER="$BUILD_NUMBER" \
    "$ROOT_DIR/script/build_and_run.sh" --stage

if [[ "$SIGNING_IDENTITY" != "-" ]]; then
    /usr/bin/codesign \
        --force \
        --options runtime \
        --timestamp \
        --sign "$SIGNING_IDENTITY" \
        "$APP_BUNDLE"
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ARCHIVE"

if [[ -n "$NOTARY_PROFILE" ]]; then
    if [[ "$SIGNING_IDENTITY" == "-" ]]; then
        echo "MINUTE_SIGNING_IDENTITY is required for notarization" >&2
        exit 2
    fi
    /usr/bin/xcrun notarytool submit "$ARCHIVE" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait
    /usr/bin/xcrun stapler staple "$APP_BUNDLE"
    /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ARCHIVE"
fi

echo "$ARCHIVE"
