# DroidHatch stable image

This directory is the self-contained build input for the validated Android
runtime image. It intentionally keeps the image inputs together instead of
depending on experimental patch contexts.

Build it from the repository root:

```sh
./image/build.sh
```

The resulting local image is `droidhatch/redroid:stable`. Its build base is
the official `redroid/redroid:14.0.0_64only-latest` image.

The image contains the validated gralloc, audio HAL, frame/input/audio agent,
and persistent DroidHatch Home APK. Its first layer applies the explicit OCI
whiteout in `bootstrap-layer/` so Apple Container can inject `hosts` and
`resolv.conf` without following Redroid's `/etc -> /system/etc` symlink.

The kernel is not part of the OCI image: Apple Container injects it when the
backend VM starts. The matching kernel is `image/kernel/vmlinux-arm64`, with
its configuration beside it.

Runtime defaults:

- container: `droidhatch-backend`
- memory: 2 GiB
- shared memory: 1 GiB
- resolution: 1280x720
- frame rate: 30 FPS
- GPU mode: guest
- audio transport: Unix socket

The files under `prebuilt/` are the exact artifacts used by the stable image.
