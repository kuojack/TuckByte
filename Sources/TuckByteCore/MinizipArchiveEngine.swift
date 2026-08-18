import Foundation
#if SWIFT_PACKAGE
import CMinizip
#endif

struct MinizipArchiveEngine {
    func createEncryptedZip(
        archiveURL: URL,
        stagingDirectoryURL: URL,
        compressionLevel: Int,
        encryption: ArchiveEncryption
    ) throws {
        let password: String
        let method: Int32
        switch encryption {
        case .none:
            return
        case .zipCrypto(let value):
            password = value
            method = Int32(TB_MZ_ENCRYPTION_ZIPCRYPTO)
        case .aes256(let value):
            password = value
            method = Int32(TB_MZ_ENCRYPTION_AES256)
        }
        guard !password.isEmpty else {
            throw ArchiveServiceError.encryptionPasswordRequired
        }

        let result = archiveURL.path.withCString { archivePath in
            stagingDirectoryURL.path.withCString { stagingPath in
                password.withCString { passwordPointer in
                    tb_mz_create_encrypted_zip(
                        archivePath,
                        stagingPath,
                        Int16(compressionLevel),
                        passwordPointer,
                        method
                    )
                }
            }
        }
        try checkResult(result, operation: "建立加密 ZIP")
    }

    func extract(
        archiveURL: URL,
        destinationURL: URL,
        password: String
    ) throws {
        guard !password.isEmpty else {
            throw ArchiveServiceError.archivePasswordRequired
        }
        let result = archiveURL.path.withCString { archivePath in
            destinationURL.path.withCString { destinationPath in
                password.withCString { passwordPointer in
                    tb_mz_extract_zip(
                        archivePath,
                        destinationPath,
                        passwordPointer
                    )
                }
            }
        }
        try checkResult(result, operation: "解壓加密 ZIP")
    }

    func encryptionMethod(for archiveURL: URL) throws -> ArchiveEncryptionMethod {
        let result = archiveURL.path.withCString {
            tb_mz_zip_encryption_method($0)
        }
        switch result {
        case Int32(TB_MZ_ENCRYPTION_NONE):
            return .none
        case Int32(TB_MZ_ENCRYPTION_ZIPCRYPTO):
            return .zipCrypto
        case Int32(TB_MZ_ENCRYPTION_AES256):
            return .aes256
        default:
            try checkResult(result, operation: "讀取 ZIP 加密資訊")
            return .none
        }
    }

    private func checkResult(_ result: Int32, operation: String) throws {
        guard result != Int32(TB_MZ_RESULT_OK) else { return }
        switch result {
        case Int32(TB_MZ_RESULT_PASSWORD_ERROR),
             Int32(TB_MZ_RESULT_CRYPT_ERROR),
             Int32(TB_MZ_RESULT_CRC_ERROR):
            throw ArchiveServiceError.incorrectArchivePassword
        default:
            throw ArchiveServiceError.archiveEngineFailed(
                operation: operation,
                code: result
            )
        }
    }
}
