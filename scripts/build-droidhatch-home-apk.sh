#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_root="$repo_root/android/home/src/main"
build_root="${DROIDHATCH_HOME_BUILD_ROOT:-$repo_root/.build/droidhatch-home}"
sdk_root="$build_root/android-sdk"
tools_archive="$build_root/commandlinetools-mac.zip"
tools_url="https://dl.google.com/android/repository/commandlinetools-mac-15641748_latest.zip"
jdk_archive="$build_root/jdk17-mac-aarch64.tar.gz"
jdk_url="https://api.adoptium.net/v3/binary/latest/17/ga/mac/aarch64/jdk/hotspot/normal/eclipse"
jdk_root="$build_root/jdk"
platform="android-35"
build_tools="35.0.0"
output_path="${DROIDHATCH_HOME_APK_OUTPUT:-$repo_root/image/prebuilt/droidhatch-home.apk}"

mkdir -p "$build_root" "$repo_root/image/prebuilt"

if [ -x "/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home/bin/java" ]; then
    jdk_root="/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home"
elif [ ! -x "$jdk_root/bin/java" ]; then
    if [ ! -f "$jdk_archive" ]; then
        curl -fsSL "$jdk_url" -o "$jdk_archive"
    fi
    rm -rf "$build_root/jdk-extract" "$jdk_root"
    mkdir -p "$build_root/jdk-extract" "$jdk_root"
    tar -xzf "$jdk_archive" -C "$build_root/jdk-extract"
    extracted_jdk=$(find "$build_root/jdk-extract" -mindepth 1 -maxdepth 1 -type d -print -quit)
    cp -R "$extracted_jdk/Contents/Home"/* "$jdk_root/"
fi

export JAVA_HOME="$jdk_root"
export PATH="$JAVA_HOME/bin:$PATH"

if [ ! -x "$sdk_root/cmdline-tools/latest/bin/sdkmanager" ]; then
    if [ ! -f "$tools_archive" ]; then
        curl -fsSL "$tools_url" -o "$tools_archive"
    fi
    rm -rf "$build_root/cmdline-tools-extract" "$sdk_root/cmdline-tools"
    mkdir -p "$sdk_root/cmdline-tools/latest"
    unzip -q -o "$tools_archive" -d "$build_root/cmdline-tools-extract"
    cp -R "$build_root/cmdline-tools-extract/cmdline-tools"/* \
        "$sdk_root/cmdline-tools/latest/"
fi

export ANDROID_HOME="$sdk_root"
export ANDROID_SDK_ROOT="$sdk_root"
sdkmanager="$sdk_root/cmdline-tools/latest/bin/sdkmanager"
yes | "$sdkmanager" --sdk_root="$sdk_root" --licenses >/dev/null 2>&1 || true
"$sdkmanager" --sdk_root="$sdk_root" \
    "platforms;$platform" \
    "build-tools;$build_tools" >/dev/null

android_jar="$sdk_root/platforms/$platform/android.jar"
tools_root="$sdk_root/build-tools/$build_tools"
classes_dir="$build_root/classes"
dex_dir="$build_root/dex"
staging_dir="$build_root/apk-staging"
unsigned_apk="$build_root/droidhatch-home-unsigned.apk"
aligned_apk="$build_root/droidhatch-home-aligned.apk"
keystore="$build_root/debug.keystore"

rm -rf "$classes_dir" "$dex_dir" "$staging_dir"
mkdir -p "$classes_dir" "$dex_dir" "$staging_dir"

find "$source_root/java" -name '*.java' -print > "$build_root/sources.list"
javac -source 8 -target 8 -classpath "$android_jar" \
    -d "$classes_dir" @"$build_root/sources.list"

"$tools_root/d8" --lib "$android_jar" --output "$dex_dir" \
    "$classes_dir"/com/droidhatch/home/*.class

"$tools_root/aapt2" link \
    -I "$android_jar" \
    --manifest "$source_root/AndroidManifest.xml" \
    --min-sdk-version 29 \
    --target-sdk-version 35 \
    --version-code 1 \
    --version-name 1.0.0 \
    -o "$unsigned_apk"

unzip -q "$unsigned_apk" -d "$staging_dir"
cp "$dex_dir/classes.dex" "$staging_dir/classes.dex"
(
    cd "$staging_dir"
    # Targeting Android 11+ requires resources.arsc to remain stored and
    # 4-byte aligned; zipalign performs the final alignment step below.
    zip -q -r -0 -D "$unsigned_apk" .
)

if [ ! -f "$keystore" ]; then
    keytool -genkeypair \
        -keystore "$keystore" \
        -storepass android \
        -keypass android \
        -alias androiddebugkey \
        -dname 'CN=Android Debug,O=Android,C=US' \
        -keyalg RSA \
        -keysize 2048 \
        -validity 10000 >/dev/null 2>&1
fi

"$tools_root/zipalign" -f 4 "$unsigned_apk" "$aligned_apk"
"$tools_root/apksigner" sign \
    --ks "$keystore" \
    --ks-pass pass:android \
    --key-pass pass:android \
    --out "$output_path" \
    "$aligned_apk"
"$tools_root/apksigner" verify "$output_path"
printf '%s\n' "DroidHatch Home APK: $output_path"
