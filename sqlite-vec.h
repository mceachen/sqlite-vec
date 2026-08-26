#ifndef SQLITE_VEC_H
#define SQLITE_VEC_H

#ifndef SQLITE_CORE
#include "sqlite3ext.h"
#else
#include "sqlite3.h"
#endif

#ifdef SQLITE_VEC_STATIC
#define SQLITE_VEC_API __attribute__((visibility("default")))
#else
#ifdef _WIN32
#define SQLITE_VEC_API __declspec(dllexport)
#else
#define SQLITE_VEC_API __attribute__((visibility("default")))
#endif
#endif

#define SQLITE_VEC_VERSION "v2.0.0"
// TODO rm
#define SQLITE_VEC_DATE "2026-08-26T03:57:04Z+0000"
#define SQLITE_VEC_SOURCE "1b27d3f5bf8eab32ee924e45289aae9ff3fe96d6"

#define SQLITE_VEC_VERSION_MAJOR 2
#define SQLITE_VEC_VERSION_MINOR 0
#define SQLITE_VEC_VERSION_PATCH 0

#ifdef __cplusplus
extern "C" {
#endif

SQLITE_VEC_API int sqlite3_vec_init(sqlite3 *db, char **pzErrMsg,
                                    const sqlite3_api_routines *pApi);

#ifdef __cplusplus
} /* end of the 'extern "C"' block */
#endif

#endif /* ifndef SQLITE_VEC_H */
