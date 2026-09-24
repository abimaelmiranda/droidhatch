#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ndk_root=${ANDROID_NDK_ROOT:-/opt/homebrew/Caskroom/android-ndk/30/AndroidNDK16248370.app/Contents/NDK}
clang="$ndk_root/toolchains/llvm/prebuilt/darwin-x86_64/bin/clang"
sysroot="$ndk_root/toolchains/llvm/prebuilt/darwin-x86_64/sysroot"
source_root="$repo_root/android/audio-hal"
header_root="$repo_root/android/gralloc/aosp-headers"
output_dir="$repo_root/image/prebuilt"
output_file="$output_dir/audio.primary.default.so"
audio_buffer_bytes=${DROIDHATCH_AUDIO_BUFFER_BYTES:-4096}

if [ ! -x "$clang" ]; then
    printf '%s\n' "Android clang not found: $clang" >&2
    exit 1
fi

mkdir -p "$output_dir"

"$clang" \
    --target=aarch64-linux-android24 \
    --sysroot="$sysroot" \
    -fPIC \
    -shared \
    -Wall \
    -Wextra \
    -Werror \
    -DDROIDHATCH_AUDIO_BUFFER_BYTES="$audio_buffer_bytes" \
    -I "$source_root/include" \
    -I "$header_root/hardware_libhardware/include_all" \
    -I "$header_root/system_core/libcutils/include" \
    -I "$header_root/system_core/libsystem/include" \
    -I "$header_root/system_logging/liblog/include" \
    "$source_root/audio_hw.c" \
    "$source_root/droidhatch_audio_tee.c" \
    -o "$output_file"

printf '%s\n' "Audio HAL compilado: $output_file"
