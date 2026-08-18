# `.tuck` benchmark and corpus policy

Run the reproducible local harness with:

```sh
swift run tuck-benchmark 64
```

The argument is input MiB. The harness creates equal parts repetitive text and
deterministic high-entropy binary data, then reports archive size, wall time and
MiB/s for Fast, Balanced and Maximum. It uses a temporary directory and deletes
the corpus when done.

Release calibration should additionally cover source/text, many small files,
executables, JSON/CSV/logs, databases, and already-compressed JPEG/PNG/MP4/PDF/
ZIP inputs. Only redistributable or locally generated data belongs in the
repository. Private customer data and data with unclear licenses must never be
checked in; record its provenance and keep only aggregate numbers.

For every tested machine record macOS version, CPU model/architecture, memory,
power mode, build configuration, corpus SHA-256, input/archive sizes, compression
and extraction wall time, peak resident memory, and encrypted index unlock time.
Compare profiles separately against Store, ZIP Deflate and upstream Zstd. Do not
claim universal speed or ratio from one machine or synthetic corpus.

## 2026-08-18 smoke run

An 8 MiB Debug-build smoke run on the available x86_64 Mac produced the
following harness output. This validates the measurement path only; it is not a
release claim or cross-machine calibration.

| Profile | Archive bytes | Create MiB/s | Extract MiB/s |
| --- | ---: | ---: | ---: |
| Fast | 4,195,283 | 147.21 | 105.90 |
| Balanced | 4,195,283 | 111.22 | 151.86 |
| Maximum | 4,195,249 | 4.10 | 134.75 |
