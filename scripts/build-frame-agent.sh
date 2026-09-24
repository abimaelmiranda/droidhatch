#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_root="$repo_root/artifacts/frame-agent"
ndk_root="${ANDROID_NDK_ROOT:-/opt/homebrew/Caskroom/android-ndk/30/AndroidNDK16248370.app/Contents/NDK}"

cmake -S "$repo_root/android/frame-agent" \
  -B "$build_root" \
  --fresh \
  -G "Unix Makefiles" \
  -DCMAKE_TOOLCHAIN_FILE="$ndk_root/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-34 \
  -DCMAKE_BUILD_TYPE=Release

cmake --build "$build_root" --target droidhatch-frame-agent -- -j4
cp "$build_root/droidhatch-frame-agent" "$repo_root/image/prebuilt/droidhatch-frame-agent"
chmod +x "$repo_root/image/prebuilt/droidhatch-frame-agent"

printf '%s\n' "Agente compilado: $build_root/droidhatch-frame-agent"
