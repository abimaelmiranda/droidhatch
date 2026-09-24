#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
native_build="$repo_root/artifacts/swift"
native_output="$repo_root/artifacts/native"

mkdir -p "$native_output"

swift build \
  --package-path "$repo_root/macos/DroidHatch.Native" \
  --configuration release \
  --product droidhatch-native \
  --build-path "$native_build" \
  -j 8

swift build \
  --package-path "$repo_root/macos/DroidHatch.Native" \
  --configuration release \
  --product droidhatch-gui \
  --build-path "$native_build" \
  -j 8

cp "$native_build/release/droidhatch-native" "$native_output/droidhatch-native"
chmod +x "$native_output/droidhatch-native"
cp "$native_build/release/droidhatch-gui" "$native_output/droidhatch-gui"
chmod +x "$native_output/droidhatch-gui"

"$repo_root/scripts/package-droidhatch-gui.sh"

printf '%s\n' "DroidHatch compilado. Native helper: $native_output/droidhatch-native"
printf '%s\n' "DroidHatch compilado. GUI: $native_output/droidhatch-gui"
printf '%s\n' "DroidHatch GUI bundle: $native_output/DroidHatch.app"
