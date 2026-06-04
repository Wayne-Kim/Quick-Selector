#!/usr/bin/env bash
# Release pipeline for quick-desktop.
#   Usage: ./release.sh <version>     e.g. ./release.sh 0.1.0
# Produces a signed/notarized/stapled DMG, signs it with Sparkle, regenerates
# appcast.xml, and creates a GitHub Release with both files attached.
#
# Configuration is loaded from .env (gitignored). See .env.example for required vars.

set -euo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "usage: $0 <version>   e.g. $0 0.1.0" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

if [[ ! -f .env ]]; then
  echo "✗ .env not found. Copy .env.example to .env and fill in your values." >&2
  exit 1
fi

# Load .env
set -a
# shellcheck disable=SC1091
source .env
set +a

REQUIRED=(APPLE_TEAM_ID APPLE_BUNDLE_ID NOTARY_KEYCHAIN_PROFILE GITHUB_OWNER GITHUB_REPO GITHUB_TOKEN SPARKLE_PUBLIC_KEY)
for var in "${REQUIRED[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "✗ $var is not set in .env" >&2
    exit 1
  fi
done

APP_NAME="quick-desktop"
SCHEME="$APP_NAME"
PROJECT="$APP_NAME.xcodeproj"
DOWNLOAD_URL_BASE="https://github.com/$GITHUB_OWNER/$GITHUB_REPO/releases/download"

DIST="$ROOT/dist"
BUILD_DIR="$DIST/build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP_PATH="$EXPORT_DIR/$APP_NAME.app"
DMG_NAME="$APP_NAME-$VERSION.dmg"
DMG_PATH="$DIST/$DMG_NAME"
APPCAST_PATH="$DIST/appcast.xml"

step() { printf "\n\033[1;34m▶ %s\033[0m\n" "$*"; }
ok()   { printf "\033[1;32m✓ %s\033[0m\n" "$*"; }
fail() { printf "\033[1;31m✗ %s\033[0m\n" "$*"; exit 1; }

step "Cleaning previous build artifacts"
rm -rf "$DIST"
mkdir -p "$BUILD_DIR" "$EXPORT_DIR"
ok "cleaned"

step "Regenerating project.yml / .xcodeproj from template (version=$VERSION)"
BUILD_NUMBER=$(date +%s)
./bin/gen-project.sh "$VERSION" "$BUILD_NUMBER"
ok "project regenerated (build=$BUILD_NUMBER)"

step "Archiving with Developer ID signing"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=macOS" \
  archive | tail -10
[[ -d "$ARCHIVE_PATH" ]] || fail "archive not produced"
ok "archived"

step "Exporting .app from archive (developer-id)"
cat >"$BUILD_DIR/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$APPLE_TEAM_ID</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
</dict>
</plist>
EOF
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" | tail -10
[[ -d "$APP_PATH" ]] || fail ".app not exported"
ok "exported"

step "Verifying code signature on .app"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign --display --verbose=2 "$APP_PATH" 2>&1 | grep -E "Authority|TeamIdentifier|Identifier" | head -10
ok "signature ok"

step "Creating DMG ($DMG_NAME)"
DMG_STAGE="$BUILD_DIR/dmg-stage"
rm -rf "$DMG_STAGE"
mkdir -p "$DMG_STAGE"
cp -R "$APP_PATH" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create \
  -volname "Quick Desktop" \
  -srcfolder "$DMG_STAGE" \
  -ov \
  -format UDZO \
  -fs HFS+ \
  "$DMG_PATH" >/dev/null
ok "dmg: $DMG_PATH ($(du -h "$DMG_PATH" | cut -f1))"

step "Signing the DMG itself"
codesign --sign "Developer ID Application" --timestamp "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"
ok "dmg signed"

step "Submitting DMG to Apple notarization service"
xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
  --wait \
  --timeout 30m
ok "notarized"

step "Stapling notarization ticket onto DMG"
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
ok "stapled"

step "Computing Sparkle signature for DMG"
SPARKLE_BIN="$ROOT/tools/sparkle/bin/sign_update"
[[ -x "$SPARKLE_BIN" ]] || fail "Sparkle sign_update not found at $SPARKLE_BIN (run setup again)"
SIGN_OUTPUT="$("$SPARKLE_BIN" "$DMG_PATH")"
echo "$SIGN_OUTPUT"
ok "sparkle-signed"

step "Generating appcast.xml"
PUB_DATE=$(LC_ALL=C date -u +"%a, %d %b %Y %H:%M:%S +0000")
DOWNLOAD_URL="$DOWNLOAD_URL_BASE/v$VERSION/$DMG_NAME"
APPCAST_URL="https://github.com/$GITHUB_OWNER/$GITHUB_REPO/releases/latest/download/appcast.xml"
SPARKLE_ATTRS=$(echo "$SIGN_OUTPUT" | tr -d '\n')
cat >"$APPCAST_PATH" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Quick Desktop</title>
    <link>$APPCAST_URL</link>
    <description>Updates for Quick Desktop</description>
    <language>en</language>
    <item>
      <title>Version $VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <enclosure
        url="$DOWNLOAD_URL"
        type="application/octet-stream"
        $SPARKLE_ATTRS />
    </item>
  </channel>
</rss>
EOF
ok "appcast.xml written"

step "Committing version bump and creating tag v$VERSION"
TAG="v$VERSION"

if ! command -v gh >/dev/null; then
  fail "gh CLI not found; install with 'brew install gh'"
fi
export GH_TOKEN="$GITHUB_TOKEN"

# Restore origin URL on exit (in case we mutated it for auth)
ORIG_ORIGIN_URL=$(git remote get-url origin)
restore_origin() { git remote set-url origin "$ORIG_ORIGIN_URL" || true; }
trap restore_origin EXIT
git remote set-url origin "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_OWNER}/${GITHUB_REPO}.git"

# Commit project.yml.template / release artifacts if user edited any tracked file.
# The generated project.yml is gitignored, so version bump itself is not committed.
if ! git diff --quiet HEAD; then
  git add -A
  git commit -m "Release $TAG (build $BUILD_NUMBER)" >/dev/null
  git push origin HEAD 2>&1 | tail -3 || true
  ok "changes committed"
else
  ok "no source changes to commit"
fi

# Ensure tag exists and is pushed
if ! git rev-parse "$TAG" >/dev/null 2>&1; then
  git tag -a "$TAG" -m "Release $TAG"
fi
git push origin "$TAG" 2>&1 | tail -3 || true

# Create or replace the GitHub release
if gh release view "$TAG" --repo "$GITHUB_OWNER/$GITHUB_REPO" >/dev/null 2>&1; then
  gh release delete "$TAG" --repo "$GITHUB_OWNER/$GITHUB_REPO" --yes --cleanup-tag=false
fi
gh release create "$TAG" \
  --repo "$GITHUB_OWNER/$GITHUB_REPO" \
  --title "Quick Desktop $VERSION" \
  --notes "Release $VERSION" \
  "$DMG_PATH" \
  "$APPCAST_PATH"

ok "release uploaded: https://github.com/$GITHUB_OWNER/$GITHUB_REPO/releases/tag/$TAG"

step "Done"
echo "DMG       : $DMG_PATH"
echo "Appcast   : $APPCAST_PATH"
echo "GH Release: https://github.com/$GITHUB_OWNER/$GITHUB_REPO/releases/tag/$TAG"
echo "Download  : $DOWNLOAD_URL"
