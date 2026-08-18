# TuckByte parser fuzzing

`main.swift` is both a deterministic mutation smoke driver and a libFuzzer entry
point. The smoke driver is available in normal SwiftPM builds:

```sh
swift run tuck-parser-fuzz Tests/TuckByteCoreTests/Fixtures/tuck-v1-store-golden.tuck 10000
```

For a coverage-guided campaign, compile the `TuckArchiveParserFuzz` target with
`FUZZING` defined and link its exported `LLVMFuzzerTestOneInput` through a
libFuzzer-capable clang driver, then seed it with
`Tests/TuckByteCoreTests/Fixtures/`. The Xcode 16 Swift driver used for the
0.8.0 smoke run does not itself accept `-sanitize=fuzzer`; do not assume a plain
`swift build` is coverage-guided. Run AddressSanitizer and UndefinedBehaviorSanitizer
campaigns separately when the selected toolchain does not support combining
them. Preserve every crashing or hanging input as a regression fixture before
fixing it.

The harness intentionally treats ordinary parser errors as expected. A crash,
trap, memory error or timeout is a failure. Because each input is materialized
as a private temporary file, long campaigns should use a fast local volume.
