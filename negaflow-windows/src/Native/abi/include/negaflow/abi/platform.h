#pragma once

/* Call convention, export marks, and the status codes every entry point answers with. */

#include "negaflow_abi_version.h"

#include <stdint.h>

#if defined(_WIN32)
#if defined(NEGAFLOW_NATIVE_EXPORTS)
#define NF_API __declspec(dllexport)
#else
#define NF_API __declspec(dllimport)
#endif
#define NF_CALL __cdecl
#else
#define NF_API
#define NF_CALL
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef uint32_t nf_status_t;

#define NF_STATUS_OK 0U
#define NF_STATUS_INVALID_ARGUMENT 1U
#define NF_STATUS_STRUCT_TOO_SMALL 2U

#ifdef __cplusplus
}
#endif
