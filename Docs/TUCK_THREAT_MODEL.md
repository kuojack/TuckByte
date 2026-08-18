# `.tuck` v1 threat model

## Security goals

- A correct password authenticates encrypted file contents, chunk metadata,
  index, names, directory layout and immutable decoding parameters.
- Wrong passwords and modified ciphertext, tags, nonces or authenticated fields
  fail before any final plaintext file is committed.
- Malformed archives cannot escape the chosen directory, overwrite existing
  files, request unchecked allocation, reuse an in-archive GCM nonce, or make
  arithmetic wrap around.
- Password change rewrites only salt, KDF parameters, wrap nonce and wrapped
  DEK; data and index keys remain domain-separated.

## Attacker capabilities

The attacker may supply an arbitrary `.tuck` or incomplete volume set, modify
any byte, choose extreme declared sizes and KDF parameters, control entry names,
and interrupt I/O. Archives and extraction directories are treated as
untrusted. The application does not assume the extension matches the magic.

## Controls in the implementation

- Argon2id v1.3 (64 MiB, 3 iterations, 4 lanes by default) derives a KEK.
- AES-256-GCM authenticates the wrapped random DEK, every encrypted chunk and
  the encrypted index. HKDF-SHA256 separates data and index keys.
- A random 64-bit prefix plus unique 32-bit sequence forms data nonces;
  `0xFFFFFFFF` is reserved for the index. Sequence reuse is rejected.
- SHA-256 detects accidental damage in unencrypted chunks and stored indexes.
- Parser limits, canonical paths, interval-overlap validation, exact record
  matching and available-space checks run before output is committed.
- Split archives are read as one bounded random-access stream without creating
  an assembled plaintext/ciphertext temporary archive.
- Cancellation and error paths delete transactional output.

## Non-goals and residual risks

- Unencrypted archives are not cryptographically authenticated; an attacker can
  recompute checksums. Use encrypted `.tuck` or an external signature where
  authenticity matters.
- Password strength remains the user's responsibility. Argon2 slows guessing
  but cannot rescue a weak password.
- File names are hidden only in encrypted archives. Total archive size, volume
  count, chunk boundaries and KDF parameters remain visible.
- v1 does not preserve symlinks, hard links, ACLs, extended attributes,
  resource forks, setuid/setgid bits or special files; it rejects unsafe types.
- Swift `String`, `Data`, CryptoKit and allocator copies cannot be guaranteed to
  be erased from all memory. Secrets are not logged, persisted or passed via
  shell arguments, but memory zeroization is best-effort.
- The app is not yet Developer ID signed/notarized. The format implementation
  has automated regression and mutation testing, but no claim of an independent
  third-party cryptographic or parser audit.
- Hardware faults, a compromised OS/process, malicious code running as the user,
  side-channel attacks and denial of service within configured limits are out of
  scope.

## Release gates

Before removing the experimental flag: run sustained coverage-guided fuzzing
with sanitizers, benchmark Argon2 on the slowest supported Intel and Apple
silicon machines, obtain independent security review, freeze golden vectors,
and publish any compatibility-breaking findings.
