#!/bin/bash
set -euo pipefail
if [[ "$(uname -s)" != Darwin ]]; then
  echo "Build requires macOS with Xcode Command Line Tools." >&2
  exit 1
fi
cd "$(dirname "$0")/.."
swift test
swift build -c release
bin_dir="$(swift build -c release --show-bin-path)"
app_dir="$PWD/dist/Aside.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$bin_dir/Aside" "$app_dir/Contents/MacOS/Aside"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
plutil -lint "$app_dir/Contents/Info.plist"
# Ad-hoc signature for local development, not Developer ID signing/notarization.
codesign --force --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
echo "Built $app_dir ($(uname -m)); not notarized."
