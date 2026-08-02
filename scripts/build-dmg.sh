#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
project_root="$(cd "$script_dir/.." && pwd -P)"
plist="$project_root/Targets/TinyDesk/SupportingFiles/Info.plist"
entitlements="$project_root/Targets/TinyDesk/SupportingFiles/TinyDesk.entitlements"
output_dir="${OUTPUT_DIR:-$project_root/dist}"

for command in xcodegen xcodebuild hdiutil codesign lipo ditto; do
    command -v "$command" >/dev/null 2>&1 || {
        echo "Missing required command: $command" >&2
        exit 1
    }
done

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
dmg_path="$output_dir/TinyDesk-$version.dmg"
checksum_path="$output_dir/TinyDesk-$version-SHA256.txt"

if [[ -e "$dmg_path" || -e "$checksum_path" ]]; then
    echo "Refusing to overwrite an existing release artifact in $output_dir" >&2
    exit 1
fi

temporary_dir="$(mktemp -d /tmp/tinydesk-dmg.XXXXXX)"
trap 'rm -rf "$temporary_dir"' EXIT
derived_data="$temporary_dir/DerivedData"
staging_dir="$temporary_dir/TinyDesk-$version"

cd "$project_root"
xcodegen generate --spec project.yml

xcodebuild \
    -project TinyDesk.xcodeproj \
    -scheme TinyDesk \
    -configuration Release \
    -derivedDataPath "$derived_data" \
    ARCHS='arm64 x86_64' \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    build

app_path="$derived_data/Build/Products/Release/TinyDesk.app"
if [[ ! -d "$app_path" ]]; then
    echo "Release app was not produced at $app_path" >&2
    exit 1
fi

executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app_path/Contents/Info.plist")"
executable_path="$app_path/Contents/MacOS/$executable_name"
lipo "$executable_path" -verify_arch arm64 x86_64

# A free, ad-hoc signature makes the bundle internally consistent. It is not a
# Developer ID signature and therefore does not imply Apple notarization.
codesign --force --deep --sign - --entitlements "$entitlements" "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"

mkdir -p "$output_dir"
mkdir -p "$staging_dir"
ditto "$app_path" "$staging_dir/TinyDesk.app"
ln -s /Applications "$staging_dir/Applications"

hdiutil create \
    -volname "TinyDesk $version" \
    -srcfolder "$staging_dir" \
    -format UDZO \
    "$dmg_path"
hdiutil verify "$dmg_path"
shasum -a 256 "$dmg_path" > "$checksum_path"

echo "Created $dmg_path"
echo "SHA-256 written to $checksum_path"
echo "This DMG is ad-hoc signed and not Developer ID-notarized."
