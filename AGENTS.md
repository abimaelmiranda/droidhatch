# DroidHatch coding rules

## Structure

- Keep one primary type per file when that improves discoverability.
- Keep each platform in its project folder: `android/home`,
  `android/frame-agent`, and `macos/DroidHatch.Native`.
- Keep generated outputs under `artifacts/` or `.build/`; do not mix them with
  source files.

## Nullability and control flow

- Treat nullable annotations as part of the design. If a value can be null,
  express that in its type.
- Use explicit null checks and guard clauses at the point where an invariant is
  required.
- Do not use the null-forgiving operator (`!`) to hide an unchecked state.
- Avoid null-coalescing fallbacks such as `?? []` or `?? new()` when they hide
  an invalid or missing state. Make the state explicit instead.
- Do not add broad defensive programming or silently recover from invalid
  states. Fail with a specific error when a required invariant is missing.
- Do not replace a missing value with a generic default such as `?? ""`,
  `?? []`, `?? new()`, or an equivalent fallback. Keep absence visible in the
  type and decide explicitly at the boundary that requires a value.
- Use early returns and guard clauses to keep the main path flat. Avoid deep
  nesting and avoid `else` when the preceding branch can return or throw.
- Use descriptive names for variables, methods, protocol fields, and native
  handles. Single-letter names are reserved for narrow mathematical loops or
  APIs that require them.

## Cross-language structure

- Swift under `macos/DroidHatch.Native` owns the macOS GUI, viewer, and platform integrations
  such as Metal and Picture in Picture.
- C++ under `android/frame-agent` owns the Android frame agent and HWC interaction.
- Keep video, audio, GPU, and container concerns in separate namespaces,
  folders, and types. Create a type or folder when it expresses a real
  responsibility or gives a future integration a stable boundary.
- Avoid oversized files. Split files when they contain independent parsing,
  transport, lifecycle, rendering, or device responsibilities. Do not split a
  cohesive operation merely to satisfy a line count.
- The frame protocol is a shared contract. Changes require updating both the
  C++ producer and the Swift consumer, plus a focused compatibility check.

## GPU and audio boundaries

- Keep CPU frame conversion separate from the future GPU renderer. A future
  Metal or shared-surface path must be able to replace the CPU presenter
  without changing HWC parsing or the CLI.
- Keep audio capture, sample formats, buffering, and output separate from video
  transport. Do not add audio fields to video frame types as a shortcut.

## Interop

- Keep macOS-specific native code in Swift unless a platform boundary is
  deliberately documented.
- Treat the frame, input, and audio protocols as shared contracts. Changes
  require updating both the Android producer and Swift consumer.

## Build

- Use `./scripts/build.sh` for the macOS binaries and bundles.
- Use `./scripts/build-frame-agent.sh` for the Android frame agent.
- Use `./scripts/build-droidhatch-home-apk.sh` for the Android Home APK.
- Use `./image/build.sh` for the stable OCI image.
