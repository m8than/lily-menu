#!/bin/bash
# Builds dist/LilyMenu.app; with --zip also dist/LilyMenu-<version>.zip and its .sha256.
#
# Environment:
#   CODESIGN_IDENTITY  signing identity (default "-": ad-hoc). A "Developer ID
#                      Application: …" identity signs with the hardened runtime.
#   NOTARY_PROFILE     a `xcrun notarytool store-credentials` profile; with a
#                      Developer ID identity and --zip, notarizes and staples.
set -euo pipefail

cd "$(dirname "$0")/.."
version=$(tr -d '[:space:]' < VERSION)
build=$(git rev-list --count HEAD 2>/dev/null || echo 1)
identity=${CODESIGN_IDENTITY:--}
app=dist/LilyMenu.app

swift build -c release --arch arm64 --product LilyMenu
bin_dir=$(swift build -c release --arch arm64 --show-bin-path)

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/LilyMenu" "$app/Contents/MacOS/LilyMenu"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
sed -e "s/__VERSION__/$version/" -e "s/__BUILD__/$build/" Resources/Info.plist > "$app/Contents/Info.plist"
plutil -lint -s "$app/Contents/Info.plist"

if [ "$identity" = - ]; then
    codesign --force --sign - "$app"
else
    codesign --force --options runtime --timestamp --sign "$identity" "$app"
fi
codesign --verify --strict "$app"
echo "built $app ($version, build $build, signed by: $identity)"

[ "${1:-}" = --zip ] || exit 0

zip=dist/LilyMenu-$version.zip
rm -f "$zip"
if [ -n "${NOTARY_PROFILE:-}" ] && [ "$identity" != - ]; then
    ditto -c -k --keepParent "$app" "$zip"
    xcrun notarytool submit "$zip" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$app"
    rm -f "$zip"
fi
ditto -c -k --keepParent "$app" "$zip"
(cd dist && shasum -a 256 "$(basename "$zip")" > "$(basename "$zip").sha256")
echo "packed $zip"
