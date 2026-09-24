#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
image_dir="$repo_root/image"
image_tag=${DROIDHATCH_IMAGE_TAG:-droidhatch/redroid:stable}

# BuildKit must receive this as a tar layer so it applies .wh.etc instead of
# following the inherited /etc symlink while copying a directory.
tar -cf "$image_dir/bootstrap-layer.tar" -C "$image_dir/bootstrap-layer" .

for required in \
    "$image_dir/Containerfile" \
    "$image_dir/bootstrap-layer.tar" \
    "$image_dir/prebuilt/gralloc.redroid.so" \
    "$image_dir/prebuilt/audio.primary.default.so" \
    "$image_dir/prebuilt/droidhatch-frame-agent" \
    "$image_dir/prebuilt/droidhatch-home.apk" \
    "$image_dir/init/droidhatch-input-audio.rc" \
    "$image_dir/init/droidhatch-home-setup.sh" \
    "$image_dir/init/droidhatch-home-setup.rc" \
    "$image_dir/kernel/vmlinux-arm64"; do
    if [ ! -f "$required" ]; then
        printf '%s\n' "Required image input missing: $required" >&2
        exit 1
    fi
done

container build \
    --tag "$image_tag" \
    --file "$image_dir/Containerfile" \
    "$image_dir"

printf '%s\n' "DroidHatch image: $image_tag"
printf '%s\n' "Kernel for runtime: $image_dir/kernel/vmlinux-arm64"
