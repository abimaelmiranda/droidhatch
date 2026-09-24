# Third-party notices

This file records third-party components incorporated into or required to
build DroidHatch. Copyright and license notices present in upstream files must
be preserved.

## Redroid / Remote Android

- Project: [remote-android/redroid-doc](https://github.com/remote-android/redroid-doc)
- Base image: `redroid/redroid:14.0.0_64only-latest`
- Use: Android 14 ARM64 userspace, Redroid boot conventions and runtime.
- Declared project license: Apache License 2.0, noting that Redroid itself
  warns that third-party modules may have different licenses.
- Upstream license documentation:
  [Redroid README — License](https://github.com/remote-android/redroid-doc#license)

DroidHatch does not claim authorship of Redroid. The final image adds
DroidHatch artifacts and configuration on top of the upstream base.

## vendor_redroid and Android Open Source Project

The snapshot under `android/gralloc/vendor_redroid/` is derived from the
shared gralloc module in
[remote-android/vendor_redroid](https://github.com/remote-android/vendor_redroid).
The preserved files carry the original Android Open Source Project notices and
are covered by the Apache License 2.0 where indicated in those files.

The AOSP headers used for compilation are kept under
`android/gralloc/aosp-headers/` together with their original `NOTICE` and
`MODULE_LICENSE_APACHE2` files. The DroidHatch patch is kept separately at
`android/gralloc/0001-preserve-buffer-metadata-and-p010.patch`.

## Swift Atomics

- Project: [apple/swift-atomics](https://github.com/apple/swift-atomics)
- Pinned version: `1.3.1`
- Revision: `0442cb5a3f98ab802acb777929fdb446bda11a34`
- License: Apache License 2.0 with the Swift Runtime Library Exception.
- License source:
  [LICENSE.txt](https://github.com/apple/swift-atomics/blob/main/LICENSE.txt)
- Distributed copy: `licenses/swift-atomics-LICENSE.txt`.

The complete Apache License 2.0 text is also preserved in the `NOTICE` files
under `android/gralloc/aosp-headers/`.

## Apple Container

The Apple Container CLI and its runtime components are external macOS
dependencies. They are not redistributed by DroidHatch; users must install
and use them under Apple's terms.

## DroidHatch code

The original DroidHatch frame-agent C++, audio HAL, Home APK, Swift GUI,
viewer, gralloc patch and build scripts are identified by the repository
structure and are covered by the [MIT License](LICENSE).

That license applies only to original DroidHatch code. It does not change the
licenses of derived or incorporated components, which remain subject to their
respective upstream notices and terms.
