#include "support/abi_text.h"

#include <cstdint>
#include <cstring>
#include <string_view>

namespace negaflow::abi::detail {

// 실패 이름 복사와 커밋 SHA1 디코드입니다.

[[nodiscard]] std::uint8_t decode_hex_nibble(const char value) noexcept {
    if (value >= '0' && value <= '9') {
        return static_cast<std::uint8_t>(value - '0');
    }
    if (value >= 'a' && value <= 'f') {
        return static_cast<std::uint8_t>(value - 'a' + 10);
    }
    if (value >= 'A' && value <= 'F') {
        return static_cast<std::uint8_t>(value - 'A' + 10);
    }
    return 0xFFU;
}

void decode_source_commit(
    const std::string_view source_commit,
    std::uint8_t (&destination)[20]) noexcept {
    if (source_commit.size() != 40U) {
        return;
    }

    for (std::size_t index = 0; index < 20U; ++index) {
        const std::uint8_t high = decode_hex_nibble(source_commit[index * 2U]);
        const std::uint8_t low = decode_hex_nibble(source_commit[(index * 2U) + 1U]);
        if (high == 0xFFU || low == 0xFFU) {
            std::memset(destination, 0, 20U);
            return;
        }
        destination[index] = static_cast<std::uint8_t>((high << 4U) | low);
    }
}

void copy_failure_name(
    const char* const source,
    char (&destination)[NF_FAILURE_NAME_CAPACITY]) noexcept {
    std::memset(destination, 0, NF_FAILURE_NAME_CAPACITY);
    if (source == nullptr) {
        return;
    }
    std::size_t index = 0U;
    while (index + 1U < NF_FAILURE_NAME_CAPACITY && source[index] != '\0') {
        destination[index] = source[index];
        ++index;
    }
}

}  // namespace negaflow::abi::detail
