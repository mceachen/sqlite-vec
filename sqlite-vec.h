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

#define SQLITE_VEC_VERSION "v1.2.0"
// TODO rm
#define SQLITE_VEC_DATE "2026-07-06T19:29:01Z-0700"
#define SQLITE_VEC_SOURCE "31e63fede66e1eb15ceb55d05ee2af133403301b"

#define SQLITE_VEC_VERSION_MAJOR 1
#define SQLITE_VEC_VERSION_MINOR 2
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
