import Foundation
import CryptoKit
import Security
#if SWIFT_PACKAGE
import CArgon2
#endif

struct TuckArchiveCrypto {
    struct Keys {
        let dataKey: SymmetricKey
        let indexKey: SymmetricKey
    }

    func randomBytes(count: Int) throws -> Data {
        var data = Data(count: count)
        let result = data.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, count, buffer.baseAddress!)
        }
        guard result == errSecSuccess else {
            throw ArchiveServiceError.tuckArchiveCryptoFailed("secure random generation")
        }
        return data
    }

    func derivePasswordKey(
        password: String,
        salt: Data,
        memoryKiB: UInt32,
        iterations: UInt32,
        parallelism: UInt32
    ) throws -> SymmetricKey {
        guard !password.isEmpty else {
            throw ArchiveServiceError.encryptionPasswordRequired
        }
        guard salt.count >= 16,
              memoryKiB >= 8 * parallelism,
              memoryKiB <= TuckArchiveLimits.maximumArgonMemoryKiB,
              iterations > 0,
              iterations <= TuckArchiveLimits.maximumArgonIterations,
              parallelism > 0,
              parallelism <= TuckArchiveLimits.maximumArgonParallelism else {
            throw ArchiveServiceError.tuckArchiveCorrupt("unsafe Argon2 parameters")
        }

        var passwordData = Data(password.utf8)
        var output = Data(count: 32)
        defer {
            passwordData.resetBytes(in: 0..<passwordData.count)
            output.resetBytes(in: 0..<output.count)
        }
        let result: Int32 = passwordData.withUnsafeBytes { passwordBuffer in
            salt.withUnsafeBytes { saltBuffer in
                output.withUnsafeMutableBytes { outputBuffer in
                    argon2id_hash_raw(
                        iterations,
                        memoryKiB,
                        parallelism,
                        passwordBuffer.baseAddress,
                        passwordBuffer.count,
                        saltBuffer.baseAddress,
                        saltBuffer.count,
                        outputBuffer.baseAddress,
                        outputBuffer.count
                    )
                }
            }
        }
        guard result == ARGON2_OK.rawValue else {
            throw ArchiveServiceError.tuckArchiveCryptoFailed(
                String(cString: argon2_error_message(result))
            )
        }
        return SymmetricKey(data: output)
    }

    func deriveArchiveKeys(dataEncryptionKey: Data, archiveID: Data) -> Keys {
        let input = SymmetricKey(data: dataEncryptionKey)
        let dataKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: input,
            salt: archiveID,
            info: Data("TUCKBYTE-DATA-v1".utf8),
            outputByteCount: 32
        )
        let indexKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: input,
            salt: archiveID,
            info: Data("TUCKBYTE-INDEX-v1".utf8),
            outputByteCount: 32
        )
        return Keys(dataKey: dataKey, indexKey: indexKey)
    }

    func seal(
        _ plaintext: Data,
        using key: SymmetricKey,
        nonceData: Data,
        authenticating aad: Data
    ) throws -> Data {
        do {
            let nonce = try AES.GCM.Nonce(data: nonceData)
            let box = try AES.GCM.seal(
                plaintext,
                using: key,
                nonce: nonce,
                authenticating: aad
            )
            var result = Data(box.ciphertext)
            result.append(contentsOf: box.tag)
            return result
        } catch {
            throw ArchiveServiceError.tuckArchiveCryptoFailed("AES-GCM seal")
        }
    }

    func open(
        _ stored: Data,
        using key: SymmetricKey,
        nonceData: Data,
        authenticating aad: Data,
        authenticationFailure: ArchiveServiceError = .incorrectArchivePassword
    ) throws -> Data {
        guard stored.count >= 16 else {
            throw ArchiveServiceError.tuckArchiveCorrupt("encrypted record is too short")
        }
        do {
            let nonce = try AES.GCM.Nonce(data: nonceData)
            let tag = stored.suffix(16)
            let ciphertext = stored.dropLast(16)
            let box = try AES.GCM.SealedBox(
                nonce: nonce,
                ciphertext: ciphertext,
                tag: tag
            )
            return try AES.GCM.open(box, using: key, authenticating: aad)
        } catch {
            throw authenticationFailure
        }
    }

    func nonce(prefix: Data, counter: UInt32) throws -> Data {
        guard prefix.count == 8 else {
            throw ArchiveServiceError.tuckArchiveCorrupt("invalid nonce prefix")
        }
        var writer = TuckBinaryWriter()
        writer.append(bytes: prefix)
        writer.append(counter)
        return writer.data
    }

    func sha256(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }
}
