//
//  zstd_decompress.h
//  lara
//
//  Streaming zstd decompressor — wraps the facebook/zstd SPM package
//  (same approach as Dopamine's DOBootstrapper)
//

#ifndef zstd_decompress_h
#define zstd_decompress_h

#include <stdbool.h>

// Decompress src_path (.tar.zst) -> dst_path (.tar)
// Returns true on success.
bool zstd_decompress_file(const char *src_path, const char *dst_path);

#endif
