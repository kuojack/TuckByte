# Third-party source and license audit

Audit date: 2026-08-18. This is a repository compliance inventory, not legal
advice or a substitute for counsel in a particular distribution jurisdiction.

| Component | Pinned upstream source | Selected license | Included notice | Runtime use |
| --- | --- | --- | --- | --- |
| Zstandard 1.5.7 | `facebook/zstd` tag `v1.5.7`, commit `f8745da6ff1ad1e7bab384bd1f9d742439278e99` | BSD 3-Clause option from upstream BSD OR GPLv2 | `ThirdParty/zstd/LICENSE` | `.tuck` compression/decompression |
| Argon2 reference 20190702 | `P-H-C/phc-winner-argon2` tag/commit `62358ba2123abd17fccf2a108a301d4b52c01a7c` | CC0 1.0 option from upstream CC0 OR Apache-2.0; included encoding/BLAKE2 files also state CC0 | `ThirdParty/argon2/LICENSE` | `.tuck` Argon2id KDF |
| minizip-ng 4.0.10 | `zlib-ng/minizip-ng` tag/commit `f3ed731e27a97e30dffe076ed5e0537daae5c1bd` | zlib License | `ThirdParty/minizip-ng/LICENSE` | encrypted ZIP create/read/extract |

Upstream references:

- <https://github.com/facebook/zstd/tree/v1.5.7>
- <https://github.com/P-H-C/phc-winner-argon2/tree/20190702>
- <https://github.com/zlib-ng/minizip-ng/tree/4.0.10>

The source headers retain upstream copyright/license notices. The packaging
script copies all three complete notices to
`TuckByte.app/Contents/Resources/ThirdPartyLicenses/`. No third-party prebuilt
binary or external SwiftPM package is present.

The app also links public Apple frameworks and invokes macOS-provided `zip`,
`zipinfo`, `tar`, and `ditto` for legacy formats. Those system components are
not redistributed from this repository and remain governed by the OS/vendor
terms. Redistributors remain responsible for Apple SDK/runtime terms, export
controls, trademarks, privacy disclosures, signing/notarization and local law.

Result: the identified vendored sources have permissive licenses compatible
with distribution alongside TuckByte's MIT-licensed code, provided notices are
retained. The audit found no copied 7-Zip, RAR, Keka, libarchive or Info-ZIP
binary in the repository. It does not establish trademark clearance for the
TuckByte name/icon or guarantee legal compliance in every jurisdiction.
