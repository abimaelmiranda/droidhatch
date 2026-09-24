# DroidHatch

Android ARM64 apps in a lightweight native environment for Apple Silicon.

DroidHatch is a personal engineering experiment: it runs one Android app at a
time inside an Apple Container backend and presents it through a native Swift
macOS interface. The project explores how far a small, purpose-built Android
runtime can go on an 8 GB Apple Silicon Mac while keeping video, audio and
input responsive.

## Current status

The validated baseline includes:

- one persistent `droidhatch-backend` container;
- Android 14 ARM64 based on Redroid;
- custom C++ frame, audio and input agent;
- DMABUF-aware custom gralloc and a Unix-socket audio path;
- custom single-app Android Home flow;
- native Swift GUI and viewer with Metal presentation;
- 1280×720 at up to 30 FPS, with a 2 GiB backend memory limit;
- automatic backend lifecycle and one active Android app at a time.

Android-side GPU acceleration is not part of the current solution. The
validated path uses the guest/Redroid runtime and keeps the presentation work
in the macOS viewer.

This is an experimental portfolio project, not a general-purpose Android
emulator or a production distribution.

## Architecture

```text
Swift GUI / viewer
        │  frame, input and audio transports
        ▼
Apple Container: droidhatch-backend
        │
        ├── Android 14 / Redroid userspace
        ├── C++ frame-agent
        ├── custom gralloc and audio HAL
        └── DroidHatch Home APK
```

The main areas are:

- `android/frame-agent/` — C++ frame capture, input injection and audio
  transport running inside Android.
- `android/audio-hal/` — custom Android audio HAL sources.
- `android/gralloc/` — Redroid/AOSP-derived gralloc sources and the DroidHatch
  buffer metadata patch.
- `android/home/` — source for the single-app Home APK.
- `macos/DroidHatch.Native/` — Swift GUI, viewer, transports and Metal
  presentation.
- `image/` — stable OCI image inputs, prebuilts, init files and the matching
  custom kernel.
- `scripts/` — local build and packaging commands.
- `.github/workflows/build-image.yml` — publishes the ARM64 image to GHCR on
  pushes to `main`.

## Requirements

- Apple Silicon Mac;
- macOS 26 or newer;
- Apple `container` CLI;
- Android NDK for rebuilding the frame agent;
- Java and Android SDK for rebuilding the Home APK.

## Build locally

Build the native macOS application:

```sh
./scripts/build.sh
```

Build the Android frame agent:

```sh
./scripts/build-frame-agent.sh
```

Build the custom audio HAL:

```sh
./scripts/build-audio-hal.sh
```

Build the Home APK:

```sh
./scripts/build-droidhatch-home-apk.sh
```

Build the stable local image:

```sh
./image/build.sh
```

The local development image is `droidhatch/redroid:stable`. Its base is the official
`redroid/redroid:14.0.0_64only-latest` image. The kernel is injected by Apple
Container at runtime; it is not embedded in the OCI image.

The GitHub Actions workflow publishes the equivalent image as:

```text
ghcr.io/<github-owner>/droidhatch/redroid:stable
```

The image build consumes the versioned artifacts in `image/prebuilt/`. When
native sources change, regenerate the relevant artifact before publishing a
new image.

The released GUI pulls the published GHCR image on first use. Set
`DROIDHATCH_IMAGE` to override it for local testing, for example:

```sh
DROIDHATCH_IMAGE=droidhatch/redroid:stable \
  /Applications/DroidHatch.app/Contents/MacOS/droidhatch-gui
```

## Runtime defaults

- container: `droidhatch-backend`;
- memory: 2 GiB;
- shared memory: 1 GiB;
- resolution: 1280×720;
- target frame rate: 30 FPS;
- Redroid GPU mode: guest;
- audio transport: Unix socket;
- one Android app open at a time.

The GUI creates and manages the backend, stores the host audio socket under
`~/.droidhatch/run/`, installs/selects APKs and opens the viewer.

## Authorship and use of AI

DroidHatch is a personal project by **Abimael Miranda**. The project direction,
architecture decisions, experiments, validation criteria and final integration
were defined and reviewed by the author.

Implementation and refactoring were performed collaboratively with the
**OpenAI Codex Agent**. Codex was used as an engineering assistant for code
generation, restructuring, debugging, documentation and build/test support.
The repository is therefore intentionally not presented as code typed entirely
by the author; the author remains responsible for the project decisions,
review, testing and integration of the resulting work.

## Third-party credits and licenses

DroidHatch incorporates or depends on work from:

- [Redroid / Remote Android](https://github.com/remote-android/redroid-doc),
  including the Android runtime conventions and the official Redroid image;
- [vendor_redroid](https://github.com/remote-android/vendor_redroid), from
  which the gralloc integration is derived;
- [Android Open Source Project](https://source.android.com/), including the
  preserved hardware headers and notices;
- [Swift Atomics](https://github.com/apple/swift-atomics), used by the native
  Swift project;
- Apple Container and its runtime, supplied by Apple and not redistributed by
  this repository.

The detailed provenance, notices and license references are maintained in
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md). Those licenses apply to the
corresponding third-party components; they do not automatically license the
original DroidHatch code.

## License

Original DroidHatch code is available under the [MIT License](LICENSE).
Third-party components remain governed by their respective licenses and
notices.

## Disclaimer

DroidHatch is an educational and experimental project. Only install and use
Android applications and media for which you have the necessary rights. The
repository does not distribute proprietary application content or user
accounts.
