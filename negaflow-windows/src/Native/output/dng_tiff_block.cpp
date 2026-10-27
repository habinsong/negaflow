#include "dng_tiff_block.h"

#include <algorithm>
#include <cstring>

namespace negaflow::output::detail {
namespace {

constexpr std::uint16_t exif_pointer_tag = 34665U;

void append_le16(std::vector<std::uint8_t>& bytes, const std::uint16_t value) {
    bytes.push_back(static_cast<std::uint8_t>(value & 0xFFU));
    bytes.push_back(static_cast<std::uint8_t>(value >> 8U));
}

void append_le32(std::vector<std::uint8_t>& bytes, const std::uint32_t value) {
    bytes.push_back(static_cast<std::uint8_t>(value & 0xFFU));
    bytes.push_back(static_cast<std::uint8_t>((value >> 8U) & 0xFFU));
    bytes.push_back(static_cast<std::uint8_t>((value >> 16U) & 0xFFU));
    bytes.push_back(static_cast<std::uint8_t>((value >> 24U) & 0xFFU));
}

[[nodiscard]] std::size_t unit_size(const TiffFieldType type) noexcept {
    switch (type) {
        case TiffFieldType::byte:
        case TiffFieldType::ascii:
        case TiffFieldType::undefined:
            return 1U;
        case TiffFieldType::short_value:
            return 2U;
        case TiffFieldType::long_value:
        case TiffFieldType::float32:
            return 4U;
        case TiffFieldType::rational:
        case TiffFieldType::signed_rational:
            return 8U;
    }
    return 1U;
}

[[nodiscard]] TiffEntry make_entry(
    const std::uint16_t tag, const TiffFieldType type, std::vector<std::uint8_t> payload) {
    TiffEntry entry{};
    entry.tag = tag;
    entry.type = type;
    entry.count = static_cast<std::uint32_t>(payload.size() / unit_size(type));
    entry.payload = std::move(payload);
    return entry;
}

void align_even(std::vector<std::uint8_t>& block) {
    if ((block.size() % 2U) != 0U) {
        block.push_back(0U);
    }
}

void patch_le32(std::vector<std::uint8_t>& block, const std::size_t at, const std::uint32_t value) {
    block[at] = static_cast<std::uint8_t>(value & 0xFFU);
    block[at + 1U] = static_cast<std::uint8_t>((value >> 8U) & 0xFFU);
    block[at + 2U] = static_cast<std::uint8_t>((value >> 16U) & 0xFFU);
    block[at + 3U] = static_cast<std::uint8_t>((value >> 24U) & 0xFFU);
}

/// 디렉터리 하나(IFD + 자기 바깥 값 영역)를 `block` 끝에 씁니다. `patch_tag` 항목의 값 자리
/// 오프셋은 `patch_offset` 에 돌려줍니다(EXIF 포인터를 나중에 고쳐 쓰기 위해서입니다).
void write_directory(
    const std::vector<TiffEntry>& entries,
    std::vector<std::uint8_t>& block,
    const std::uint16_t patch_tag,
    std::size_t& patch_offset) {
    align_even(block);
    const std::size_t directory_start = block.size();
    const std::size_t directory_size = 2U + (entries.size() * 12U) + 4U;
    std::size_t out_of_line_cursor = directory_start + directory_size;
    std::vector<std::uint8_t> out_of_line{};

    append_le16(block, static_cast<std::uint16_t>(entries.size()));
    for (const TiffEntry& entry : entries) {
        append_le16(block, entry.tag);
        append_le16(block, static_cast<std::uint16_t>(entry.type));
        append_le32(block, entry.count);
        if (entry.payload.size() <= 4U) {
            if (entry.tag == patch_tag) {
                patch_offset = block.size();
            }
            block.insert(block.end(), entry.payload.begin(), entry.payload.end());
            block.insert(block.end(), 4U - entry.payload.size(), 0U);
        } else {
            if ((out_of_line_cursor % 2U) != 0U) {
                out_of_line.push_back(0U);
                ++out_of_line_cursor;
            }
            append_le32(block, static_cast<std::uint32_t>(out_of_line_cursor));
            out_of_line.insert(out_of_line.end(), entry.payload.begin(), entry.payload.end());
            out_of_line_cursor += entry.payload.size();
        }
    }
    append_le32(block, 0U);  // 다음 IFD 없음
    block.insert(block.end(), out_of_line.begin(), out_of_line.end());
}

}  // namespace

TiffEntry tiff_bytes(const std::uint16_t tag, const std::vector<std::uint8_t>& values) {
    return make_entry(tag, TiffFieldType::byte, values);
}

TiffEntry tiff_undefined(const std::uint16_t tag, const std::vector<std::uint8_t>& values) {
    return make_entry(tag, TiffFieldType::undefined, values);
}

TiffEntry tiff_shorts(const std::uint16_t tag, const std::vector<std::uint16_t>& values) {
    std::vector<std::uint8_t> payload{};
    payload.reserve(values.size() * 2U);
    for (const std::uint16_t value : values) {
        append_le16(payload, value);
    }
    return make_entry(tag, TiffFieldType::short_value, std::move(payload));
}

TiffEntry tiff_longs(const std::uint16_t tag, const std::vector<std::uint32_t>& values) {
    std::vector<std::uint8_t> payload{};
    payload.reserve(values.size() * 4U);
    for (const std::uint32_t value : values) {
        append_le32(payload, value);
    }
    return make_entry(tag, TiffFieldType::long_value, std::move(payload));
}

TiffEntry tiff_floats(const std::uint16_t tag, const std::vector<float>& values) {
    std::vector<std::uint8_t> payload{};
    payload.reserve(values.size() * 4U);
    for (const float value : values) {
        std::uint32_t bits = 0U;
        std::memcpy(&bits, &value, sizeof(bits));
        append_le32(payload, bits);
    }
    return make_entry(tag, TiffFieldType::float32, std::move(payload));
}

TiffEntry tiff_rationals(
    const std::uint16_t tag,
    const std::vector<std::pair<std::uint32_t, std::uint32_t>>& values) {
    std::vector<std::uint8_t> payload{};
    payload.reserve(values.size() * 8U);
    for (const auto& [numerator, denominator] : values) {
        append_le32(payload, numerator);
        append_le32(payload, denominator);
    }
    return make_entry(tag, TiffFieldType::rational, std::move(payload));
}

TiffEntry tiff_signed_rationals(
    const std::uint16_t tag,
    const std::vector<std::pair<std::int32_t, std::int32_t>>& values) {
    std::vector<std::uint8_t> payload{};
    payload.reserve(values.size() * 8U);
    for (const auto& [numerator, denominator] : values) {
        append_le32(payload, static_cast<std::uint32_t>(numerator));
        append_le32(payload, static_cast<std::uint32_t>(denominator));
    }
    return make_entry(tag, TiffFieldType::signed_rational, std::move(payload));
}

std::vector<std::uint8_t> ascii_bytes(const std::wstring& text) {
    std::vector<std::uint8_t> bytes{};
    bytes.reserve(text.size());
    for (const wchar_t character : text) {
        bytes.push_back(
            character >= 0 && character < 0x80 ? static_cast<std::uint8_t>(character)
                                                : static_cast<std::uint8_t>('?'));
    }
    return bytes;
}

TiffEntry tiff_ascii(const std::uint16_t tag, const std::wstring& text) {
    std::vector<std::uint8_t> payload = ascii_bytes(text);
    payload.push_back(0U);
    return make_entry(tag, TiffFieldType::ascii, std::move(payload));
}

TiffEntry tiff_ascii(const std::uint16_t tag, const std::string& text) {
    std::vector<std::uint8_t> payload{};
    payload.reserve(text.size() + 1U);
    for (const char character : text) {
        payload.push_back(static_cast<unsigned char>(character) < 0x80U
                              ? static_cast<std::uint8_t>(character)
                              : static_cast<std::uint8_t>('?'));
    }
    payload.push_back(0U);
    return make_entry(tag, TiffFieldType::ascii, std::move(payload));
}

std::vector<std::uint8_t> make_tiff_header_block(
    std::vector<TiffEntry> ifd0,
    std::vector<TiffEntry> exif) {
    if (!exif.empty()) {
        // 포인터 값은 EXIF IFD 위치를 안 뒤에 고쳐 쓴다. 자리만 먼저 잡습니다.
        ifd0.push_back(tiff_longs(exif_pointer_tag, {0U}));
    }
    const auto by_tag = [](const TiffEntry& left, const TiffEntry& right) noexcept {
        return left.tag < right.tag;
    };
    std::sort(ifd0.begin(), ifd0.end(), by_tag);
    std::sort(exif.begin(), exif.end(), by_tag);

    std::vector<std::uint8_t> block{0x49U, 0x49U, 42U, 0U};  // "II" + 42, 리틀엔디언
    append_le32(block, 8U);                                  // IFD0 오프셋

    std::size_t pointer_field_offset = 0U;
    write_directory(ifd0, block, exif.empty() ? std::uint16_t{0U} : exif_pointer_tag, pointer_field_offset);
    if (!exif.empty()) {
        align_even(block);
        patch_le32(block, pointer_field_offset, static_cast<std::uint32_t>(block.size()));
        std::size_t unused = 0U;
        write_directory(exif, block, 0U, unused);
    }
    return block;
}

}  // namespace negaflow::output::detail
