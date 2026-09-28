#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
gui_binary="$repo_root/artifacts/native/droidhatch-gui"
viewer_resources_bundle="$repo_root/artifacts/swift/out/Products/Release/DroidHatch.Native_DroidHatchViewer.bundle"
aapt2_binary="$repo_root/artifacts/tools/aapt2"
kernel_binary="$repo_root/image/kernel/vmlinux-arm64"
gui_bundle="$repo_root/artifacts/native/DroidHatch.app"
gui_contents="$gui_bundle/Contents"

if [ ! -x "$gui_binary" ]; then
    printf '%s\n' "GUI binary not found: $gui_binary" >&2
    exit 1
fi
if [ ! -d "$viewer_resources_bundle" ]; then
    printf '%s\n' "Viewer resources bundle not found: $viewer_resources_bundle" >&2
    exit 1
fi
if [ ! -x "$aapt2_binary" ]; then
    printf '%s\n' "aapt2 not found: $aapt2_binary" >&2
    exit 1
fi
if [ ! -r "$kernel_binary" ]; then
    printf '%s\n' "DroidHatch kernel not found: $kernel_binary" >&2
    exit 1
fi

rm -rf "$gui_bundle"
mkdir -p "$gui_contents/MacOS" \
    "$gui_contents/Resources/tools" "$gui_contents/Resources/kernel"
cp "$repo_root/macos/DroidHatch.Native/Resources/DroidHatchGUI-Info.plist" \
    "$gui_contents/Info.plist"
cp "$gui_binary" "$gui_contents/MacOS/droidhatch-gui"
chmod +x "$gui_contents/MacOS/droidhatch-gui"
cp "$aapt2_binary" "$gui_contents/Resources/tools/aapt2"
chmod +x "$gui_contents/Resources/tools/aapt2"
cp "$kernel_binary" "$gui_contents/Resources/kernel/vmlinux-arm64"
chmod 644 "$gui_contents/Resources/kernel/vmlinux-arm64"
cp -R "$viewer_resources_bundle" \
    "$gui_contents/Resources/DroidHatch.Native_DroidHatchViewer.bundle"
cp "$repo_root/THIRD_PARTY_NOTICES.md" \
    "$gui_contents/Resources/THIRD_PARTY_NOTICES.md"

printf '%s\n' "DroidHatch GUI bundle: $gui_bundle"
