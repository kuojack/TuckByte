#ifndef TUCKBYTE_MINIZIP_H
#define TUCKBYTE_MINIZIP_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
    TB_MZ_ENCRYPTION_NONE = 0,
    TB_MZ_ENCRYPTION_ZIPCRYPTO = 1,
    TB_MZ_ENCRYPTION_AES256 = 2
};

enum {
    TB_MZ_RESULT_OK = 0,
    TB_MZ_RESULT_CRC_ERROR = -105,
    TB_MZ_RESULT_CRYPT_ERROR = -106,
    TB_MZ_RESULT_PASSWORD_ERROR = -108
};

int32_t tb_mz_create_encrypted_zip(
    const char *archive_path,
    const char *staging_root_path,
    int16_t compression_level,
    const char *password,
    int32_t encryption_method
);

int32_t tb_mz_extract_zip(
    const char *archive_path,
    const char *destination_path,
    const char *password
);

int32_t tb_mz_zip_encryption_method(const char *archive_path);

#ifdef __cplusplus
}
#endif

#endif
