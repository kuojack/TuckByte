# ZipForge

ZipForge is an early macOS archive utility written in Swift. The first version focuses on a usable local workflow: open a zip archive, inspect entries, extract to a chosen folder, create a new zip from files or folders, and wrap an existing ZIP in another compressed layer.

## Current scope

- SwiftUI macOS interface
- Drag and drop archive selection
- Drag and drop compression queue for files and folders
- Finder right-click actions for adding items to ZipForge and extracting ZIP files in place
- Background Finder extraction with completion notifications
- Wrap an opened ZIP in another ZIP layer with its own compression level or password
- Compression settings panel with format choice, speed presets, compression level, and traditional ZIP password protection
- Zip inspection through `/usr/bin/zipinfo` and `/usr/bin/tar`
- Zip extraction through `/usr/bin/ditto`
- Zip creation through `/usr/bin/zip`
- Friendly unsupported-format handling for `.7z`, `.rar`, `.tar`, `.gz`, and unknown files

## Build and test

```sh
swift test
swift run ZipForge
xcodebuild -project ZipForge.xcodeproj -scheme ZipForge -configuration Release build
```

## Package a local app

```sh
Scripts/package_app.sh
Scripts/package_dmg.sh
```

The packaging scripts create `dist/ZipForge.app` and `dist/ZipForge.dmg`. The Xcode build embeds `ZipForgeFinderSync.appex`, then the packaging script applies ad-hoc signatures to the extension and containing app. This local sharing build is not notarized for public distribution.

## Enable Finder integration

1. Drag `ZipForge.app` from the DMG into `/Applications`.
2. Launch ZipForge once and use its Finder integration prompt or Settings window.
3. Open the macOS extension management interface and enable **ZipForge Finder**.
4. Allow notifications if background extraction completion should remain unobtrusive.

After the extension is enabled, right-click any Finder selection and choose **加入壓縮檔**. When every selected item is a ZIP file, **解壓縮至此** is also available. Finder extraction creates a sibling folder named after each archive; existing names receive a numeric suffix and are never overwritten.

## Product notes

![ZipForge icon](Resources/AppIcon.svg)

The first compression settings implementation maps speed presets to standard ZIP compression levels and passes the selected level to `/usr/bin/zip`. Password protection uses traditional ZIP encryption through the system zip tool, not AES. ZIP is the only creation format in this build; 7z, RAR, and TAR are product options reserved for the next archive engine.

`swift test` and full SwiftPM builds require a complete Xcode installation because XCTest must be available. With Command Line Tools only, core source syntax can still be checked with `swiftc -parse Sources/ZipForgeCore/*.swift`.

The current build is designed for local development and direct execution, not App Store distribution. Later versions can add libarchive/7z support, password handling for source archives, Developer ID signing, and notarization.
