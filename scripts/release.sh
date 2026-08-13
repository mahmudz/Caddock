#!/usr/bin/env bash
# Build, notarize, and package CaddyManager as a distributable .dmg
#
# Prerequisites
#   1. "Developer ID Application" certificate in the login keychain
#   2. Notary credentials stored once via:
#        xcrun notarytool store-credentials "CaddyManager-notary" \
#          --apple-id "you@example.com" \
#          --team-id "SP792GFSPZ" \
#          --password "<app-specific-password>"
#      Or set APPLE_ID / APPLE_APP_SPECIFIC_PASSWORD / APPLE_TEAM_ID
#      Or set APPLE_API_KEY_PATH / APPLE_API_KEY / APPLE_API_ISSUER (App Store Connect API key)
#
# Usage
#   ./scripts/release.sh
#   ./scripts/release.sh --skip-notarize          # local unsigned-for-distribution dry run still signs Developer ID
#   ./scripts/release.sh --skip-notarize --skip-sign   # Debug-style local DMG only (Apple Development)
#   NOTARY_PROFILE=MyProfile ./scripts/release.sh
#
# Output
#   dist/CaddyManager-<version>.dmg

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="CaddyManager"
PROJECT="CaddyManager.xcodeproj"
SCHEME="CaddyManager"
CONFIGURATION="Release"
TEAM_ID="${APPLE_TEAM_ID:-SP792GFSPZ}"
NOTARY_PROFILE="${NOTARY_PROFILE:-CaddyManager-notary}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
SKIP_NOTARIZE=0
SKIP_SIGN=0

BUILD_DIR="${BUILD_DIR:-$ROOT/build/release}"
DIST_DIR="${DIST_DIR:-$ROOT/dist}"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
DMG_STAGE="$BUILD_DIR/dmg-root"

usage() {
  sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

log()  { printf '==> %s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage 0 ;;
    --skip-notarize) SKIP_NOTARIZE=1; shift ;;
    --skip-sign) SKIP_SIGN=1; shift ;;
    --team-id) TEAM_ID="${2:?}"; shift 2 ;;
    --identity) SIGN_IDENTITY="${2:?}"; shift 2 ;;
    --notary-profile) NOTARY_PROFILE="${2:?}"; shift 2 ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
done

have xcodebuild || die "xcodebuild not found"
have hdiutil || die "hdiutil not found"
have ditto || die "ditto not found"

resolve_sign_identity() {
  if [[ -n "$SIGN_IDENTITY" ]]; then
    printf '%s\n' "$SIGN_IDENTITY"
    return
  fi

  local identities
  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"

  if [[ "$SKIP_SIGN" -eq 1 ]]; then
    local dev
    dev="$(printf '%s\n' "$identities" | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -n1)"
    [[ -n "$dev" ]] || die "no Apple Development identity found"
    printf '%s\n' "$dev"
    return
  fi

  local devid
  devid="$(printf '%s\n' "$identities" | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -n1)"
  [[ -n "$devid" ]] || die "no Developer ID Application certificate found.
Install one from https://developer.apple.com/account/resources/certificates/list
(type: Developer ID Application), then re-run.
Current identities:
$identities"
  printf '%s\n' "$devid"
}

app_version() {
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$1/Contents/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
      "$1/Contents/Info.plist"
}

notarize_item() {
  local item="$1"
  local args=()

  if [[ -n "${APPLE_API_KEY_PATH:-}" && -n "${APPLE_API_KEY:-}" && -n "${APPLE_API_ISSUER:-}" ]]; then
    args=(--key "$APPLE_API_KEY_PATH" --key-id "$APPLE_API_KEY" --issuer "$APPLE_API_ISSUER")
  elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
    args=(--apple-id "$APPLE_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" --team-id "$TEAM_ID")
  else
    args=(--keychain-profile "$NOTARY_PROFILE")
  fi

  log "Submitting for notarization: $(basename "$item")"
  xcrun notarytool submit "$item" "${args[@]}" --wait

  log "Stapling notarization ticket"
  xcrun stapler staple "$item"
  xcrun stapler validate "$item"
}

SIGN_IDENTITY="$(resolve_sign_identity)"
log "Signing identity: $SIGN_IDENTITY"
log "Team ID: $TEAM_ID"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

# --- Archive -----------------------------------------------------------------
log "Archiving $SCHEME ($CONFIGURATION)"

ARCHIVE_ARGS=(
  -project "$PROJECT"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -archivePath "$ARCHIVE_PATH"
  -destination "generic/platform=macOS"
  COMPILER_INDEX_STORE_ENABLE=NO
  DEVELOPMENT_TEAM="$TEAM_ID"
)

if [[ "$SKIP_SIGN" -eq 0 ]]; then
  ARCHIVE_ARGS+=(
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY"
    "OTHER_CODE_SIGN_FLAGS=--timestamp --options=runtime"
  )
fi

if have xcpretty; then
  xcodebuild "${ARCHIVE_ARGS[@]}" archive | xcpretty --color
else
  xcodebuild "${ARCHIVE_ARGS[@]}" archive
fi

APP_IN_ARCHIVE="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
[[ -d "$APP_IN_ARCHIVE" ]] || die "archive missing app at $APP_IN_ARCHIVE"

# Prefer exportArchive so nested helper / LaunchDaemon resources get a clean Developer ID pass.
log "Exporting Developer ID app"
mkdir -p "$EXPORT_DIR"
EXPORT_PLIST="$BUILD_DIR/ExportOptions.plist"
cat > "$EXPORT_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>developer-id</string>
	<key>teamID</key>
	<string>${TEAM_ID}</string>
	<key>signingStyle</key>
	<string>manual</string>
	<key>signingCertificate</key>
	<string>Developer ID Application</string>
</dict>
</plist>
EOF

APP=""
if [[ "$SKIP_SIGN" -eq 0 ]]; then
  if xcodebuild -exportArchive \
      -archivePath "$ARCHIVE_PATH" \
      -exportPath "$EXPORT_DIR" \
      -exportOptionsPlist "$EXPORT_PLIST"; then
    APP="$EXPORT_DIR/$APP_NAME.app"
  else
    log "exportArchive failed; falling back to archive product + deep re-sign"
    APP="$EXPORT_DIR/$APP_NAME.app"
    mkdir -p "$EXPORT_DIR"
    ditto "$APP_IN_ARCHIVE" "$APP"
    codesign --force --deep --options runtime --timestamp \
      --sign "$SIGN_IDENTITY" "$APP"
  fi
else
  APP="$EXPORT_DIR/$APP_NAME.app"
  mkdir -p "$EXPORT_DIR"
  ditto "$APP_IN_ARCHIVE" "$APP"
fi

[[ -d "$APP" ]] || die "exported app missing at $APP"

VERSION="$(app_version "$APP")"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"

log "Verifying code signature"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv --verbose=4 "$APP" 2>&1 | grep -E 'Authority|TeamIdentifier|Runtime|Identifier' || true

# --- DMG ---------------------------------------------------------------------
log "Building DMG"
rm -rf "$DMG_STAGE"
mkdir -p "$DMG_STAGE"
ditto "$APP" "$DMG_STAGE/$APP_NAME.app"
ln -s /Applications "$DMG_STAGE/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGE" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$DMG_PATH"

# --- Notarize ----------------------------------------------------------------
if [[ "$SKIP_NOTARIZE" -eq 1 || "$SKIP_SIGN" -eq 1 ]]; then
  log "Skipping notarization (--skip-notarize / --skip-sign)"
else
  have xcrun || die "xcrun not found"
  notarize_item "$DMG_PATH"

  log "Gatekeeper assessment"
  spctl --assess --type open --context context:primary-signature -v "$DMG_PATH" || true
fi

log "Done: $DMG_PATH"
ls -lh "$DMG_PATH"
