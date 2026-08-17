#pragma once

#include "negaflow_abi.h"

#include <cstdint>
#include <string_view>

namespace negaflow::abi::detail {

// ABI 문자 버퍼 헬퍼입니다. 실패 이름과 커밋 SHA1 만 다룹니다.

void decode_source_commit(
    const std::string_view source_commit,
    std::uint8_t (&destination)[20]) noexcept;

void copy_failure_name(
    const char* const source,
    char (&destination)[NF_FAILURE_NAME_CAPACITY]) noexcept;

}  // namespace negaflow::abi::detail
