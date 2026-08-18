# Third-Party and Platform Notices

This repository does not vendor third-party Swift packages or prebuilt
third-party binaries. It vendors the following upstream C source releases.

## Zstandard

TuckByte includes Zstandard 1.5.7 source from <https://github.com/facebook/zstd>
for native `.tuck` compression and decompression. Zstandard is distributed
under the BSD 3-Clause License. The complete notice is preserved at
`ThirdParty/zstd/LICENSE` and copied into packaged application resources.

## Argon2

TuckByte includes the official Argon2 reference source release `20190702`
(Argon2 v1.3) from <https://github.com/P-H-C/phc-winner-argon2> for `.tuck`
password key derivation. The vendored files are distributed under the CC0 1.0
Universal dedication, as selected by the upstream dual-license notice. The
complete notice is preserved at `ThirdParty/argon2/LICENSE` and copied into
packaged application resources.

## minizip-ng

TuckByte includes minizip-ng 4.0.10 source code from
<https://github.com/zlib-ng/minizip-ng> for WinZip AES-256 and traditional
ZipCrypto creation, encrypted ZIP detection, and password-protected ZIP
extraction.

minizip-ng is distributed under the zlib License. The complete upstream license
notice is preserved at `ThirdParty/minizip-ng/LICENSE` and is copied into the
packaged application's resources. TuckByte's MIT License does not replace or
alter the minizip-ng license.

## macOS system tools

At runtime, TuckByte invokes tools that are already installed as part of macOS:

- `/usr/bin/zip`
- `/usr/bin/zipinfo`
- `/usr/bin/tar`
- `/usr/bin/ditto`

These tools are not copied into this repository or the TuckByte application
bundle. Their copyright and license terms are provided by the operating system
and remain independent from TuckByte's MIT License. The `zip` and `zipinfo`
commands are historically associated with the Info-ZIP project and may be
subject to the Info-ZIP License. On macOS, `/usr/bin/tar` is based on the
system-provided libarchive implementation and is used for 7z listing and
extraction; TuckByte does not copy libarchive into its application bundle.

## Apple frameworks and development tools

TuckByte links against public Apple frameworks, including SwiftUI, AppKit,
Foundation, FinderSync, UserNotifications, and OSLog. Building TuckByte
requires Xcode and the macOS SDK, which are governed by Apple's applicable
license agreements.

Xcode may copy Apple or Swift runtime support libraries, such as
`libswift_Concurrency.dylib`, into locally packaged application bundles for
deployment compatibility. Build outputs are excluded from this source
repository. Anyone distributing compiled TuckByte binaries is responsible for
complying with the applicable Apple and Swift runtime terms.

## Build-time standard libraries

The packaging script uses Python 3 standard-library modules and zlib support to
generate the local application icon. No Python package is installed or bundled
with TuckByte.

## Project assets

The TuckByte name, source code, and repository-native icon artwork in this
repository are provided under the repository's MIT License unless a file states
otherwise.

The project's MIT License does not replace or relicense Zstandard, Argon2,
minizip-ng, Apple components, or macOS system tools. A source or binary
distributor must retain the corresponding notices.
