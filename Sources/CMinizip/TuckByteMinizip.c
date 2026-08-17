#include "TuckByteMinizip.h"

#include "mz.h"
#include "mz_strm.h"
#include "mz_zip.h"
#include "mz_zip_rw.h"

int32_t tb_mz_create_encrypted_zip(
    const char *archive_path,
    const char *staging_root_path,
    int16_t compression_level,
    const char *password,
    int32_t encryption_method
) {
    if (!archive_path || !staging_root_path || !password || password[0] == '\0')
        return MZ_PASSWORD_ERROR;
    if (encryption_method != TB_MZ_ENCRYPTION_ZIPCRYPTO &&
        encryption_method != TB_MZ_ENCRYPTION_AES256)
        return MZ_PARAM_ERROR;

    void *writer = mz_zip_writer_create();
    if (!writer)
        return MZ_MEM_ERROR;

    mz_zip_writer_set_compress_method(writer, MZ_COMPRESS_METHOD_DEFLATE);
    mz_zip_writer_set_compress_level(writer, compression_level);
    mz_zip_writer_set_password(writer, password);
    mz_zip_writer_set_aes(
        writer,
        encryption_method == TB_MZ_ENCRYPTION_AES256 ? 1 : 0
    );
    mz_zip_writer_set_store_links(writer, 1);

    int32_t result = mz_zip_writer_open_file(writer, archive_path, 0, 0);
    if (result == MZ_OK) {
        result = mz_zip_writer_add_path(
            writer,
            staging_root_path,
            staging_root_path,
            0,
            1
        );
    }

    int32_t close_result = mz_zip_writer_close(writer);
    mz_zip_writer_delete(&writer);
    return result == MZ_OK ? close_result : result;
}

int32_t tb_mz_extract_zip(
    const char *archive_path,
    const char *destination_path,
    const char *password
) {
    if (!archive_path || !destination_path)
        return MZ_PARAM_ERROR;

    void *reader = mz_zip_reader_create();
    if (!reader)
        return MZ_MEM_ERROR;

    if (password && password[0] != '\0')
        mz_zip_reader_set_password(reader, password);

    int32_t result = mz_zip_reader_open_file(reader, archive_path);
    if (result == MZ_OK)
        result = mz_zip_reader_save_all(reader, destination_path);

    int32_t close_result = mz_zip_reader_close(reader);
    mz_zip_reader_delete(&reader);
    return result == MZ_OK ? close_result : result;
}

int32_t tb_mz_zip_encryption_method(const char *archive_path) {
    if (!archive_path)
        return MZ_PARAM_ERROR;

    void *reader = mz_zip_reader_create();
    if (!reader)
        return MZ_MEM_ERROR;

    int32_t result = mz_zip_reader_open_file(reader, archive_path);
    int32_t encryption_method = TB_MZ_ENCRYPTION_NONE;
    if (result == MZ_OK)
        result = mz_zip_reader_goto_first_entry(reader);

    while (result == MZ_OK) {
        mz_zip_file *file_info = NULL;
        result = mz_zip_reader_entry_get_info(reader, &file_info);
        if (result != MZ_OK)
            break;
        if (file_info && (file_info->flag & MZ_ZIP_FLAG_ENCRYPTED)) {
            encryption_method = file_info->aes_version != 0
                ? TB_MZ_ENCRYPTION_AES256
                : TB_MZ_ENCRYPTION_ZIPCRYPTO;
            break;
        }
        result = mz_zip_reader_goto_next_entry(reader);
    }

    if (result == MZ_END_OF_LIST)
        result = MZ_OK;
    mz_zip_reader_close(reader);
    mz_zip_reader_delete(&reader);
    return result == MZ_OK ? encryption_method : result;
}
