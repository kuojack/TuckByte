# Third-Party and Platform Notices

This repository does not vendor third-party Swift packages, archive engines, or
prebuilt third-party binaries.

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
subject to the Info-ZIP License.

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
