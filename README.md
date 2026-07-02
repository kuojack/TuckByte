# ZipForge

ZipForge is an early macOS archive utility written in Swift. The first version focuses on a usable local workflow: open a zip archive, inspect entries, extract to a chosen folder, and create a new zip from files or folders.

## Current scope

- SwiftUI macOS interface
- Drag and drop archive selection
- Zip inspection through `/usr/bin/zipinfo`
- Zip extraction through `/usr/bin/ditto`
- Zip creation through `/usr/bin/zip`
- Friendly unsupported-format handling for `.7z`, `.rar`, `.tar`, `.gz`, and unknown files

## Build and test

```sh
swift test
swift run ZipForge
```

The initial build is designed for local development and direct execution, not App Store distribution. Later versions can add libarchive/7z support, password handling, Finder integration, app signing, and a packaged `.app` release.
