#pragma once

// Rebuilds the colorsync-icm-parity-v1 input profile from the synthesis rule in
// Negaflow.Windows/docs/research/colorsync-icm-parity-profile.md.
//
// The rule is normative and the reproduced bytes must hash to the SHA-256 the
// macOS reference recorded. If they do not, the two colour management systems
// are reading different profiles and any output difference proves nothing, so
// the caller must stop rather than report a divergence.

#include <array>
#include <cstddef>
#include <cstdint>
#include <string_view>
#include <vector>

namespace negaflow::fixtures {
namespace detail {

inline void append_be32(std::vector<std::uint8_t>& bytes, const std::uint32_t value) {
    bytes.push_back(static_cast<std::uint8_t>((value >> 24U) & 0xFFU));
    bytes.push_back(static_cast<std::uint8_t>((value >> 16U) & 0xFFU));
    bytes.push_back(static_cast<std::uint8_t>((value >> 8U) & 0xFFU));
    bytes.push_back(static_cast<std::uint8_t>(value & 0xFFU));
}

inline void append_be16(std::vector<std::uint8_t>& bytes, const std::uint16_t value) {
    bytes.push_back(static_cast<std::uint8_t>((value >> 8U) & 0xFFU));
    bytes.push_back(static_cast<std::uint8_t>(value & 0xFFU));
}

inline void append_signature(
    std::vector<std::uint8_t>& bytes,
    const std::string_view signature) {
    for (const char character : signature) {
        bytes.push_back(static_cast<std::uint8_t>(character));
    }
}

inline void append_zeros(std::vector<std::uint8_t>& bytes, const std::size_t count) {
    bytes.insert(bytes.end(), count, static_cast<std::uint8_t>(0));
}

[[nodiscard]] inline std::size_t align4(const std::size_t value) noexcept {
    return (value + 3U) & ~static_cast<std::size_t>(3U);
}

[[nodiscard]] inline std::vector<std::uint8_t> xyz_type(
    const std::uint32_t x,
    const std::uint32_t y,
    const std::uint32_t z) {
    std::vector<std::uint8_t> data;
    append_signature(data, "XYZ ");
    append_be32(data, 0U);
    append_be32(data, x);
    append_be32(data, y);
    append_be32(data, z);
    return data;
}

// count = 1 means a single u8Fixed8Number gamma. 563 / 256 is 2.19921875, which
// is what the encoding can represent; it is deliberately not 2.2.
[[nodiscard]] inline std::vector<std::uint8_t> curve_gamma(const std::uint16_t encoded_gamma) {
    std::vector<std::uint8_t> data;
    append_signature(data, "curv");
    append_be32(data, 0U);
    append_be32(data, 1U);
    append_be16(data, encoded_gamma);
    return data;
}

// ICC v2 textDescriptionType always carries the empty Unicode and ScriptCode
// blocks after the ASCII block. The 67-byte ScriptCode buffer cannot be omitted.
[[nodiscard]] inline std::vector<std::uint8_t> text_description(const std::string_view ascii) {
    std::vector<std::uint8_t> data;
    append_signature(data, "desc");
    append_be32(data, 0U);
    append_be32(data, static_cast<std::uint32_t>(ascii.size() + 1U));
    append_signature(data, ascii);
    data.push_back(0U);
    append_be32(data, 0U);
    append_be32(data, 0U);
    append_be16(data, 0U);
    data.push_back(0U);
    append_zeros(data, 67U);
    return data;
}

[[nodiscard]] inline std::vector<std::uint8_t> text_type(const std::string_view ascii) {
    std::vector<std::uint8_t> data;
    append_signature(data, "text");
    append_be32(data, 0U);
    append_signature(data, ascii);
    data.push_back(0U);
    return data;
}

}  // namespace detail

[[nodiscard]] inline std::vector<std::uint8_t> build_synthetic_parity_profile() {
    constexpr std::uint32_t declared_bytes = 556U;
    constexpr std::string_view description = "Negaflow Synthetic Scanner RGB v1";
    constexpr std::string_view copyright =
        "Negaflow synthetic parity fixture. No rights asserted.";

    std::vector<std::uint8_t> header;
    header.reserve(128U);
    detail::append_be32(header, declared_bytes);
    detail::append_be32(header, 0U);
    detail::append_be32(header, 0x02100000U);
    detail::append_signature(header, "scnr");
    detail::append_signature(header, "RGB ");
    detail::append_signature(header, "XYZ ");
    // Fixed creation date. A real timestamp would change the bytes every run.
    for (const std::uint16_t field : {std::uint16_t{2026}, std::uint16_t{1}, std::uint16_t{1},
                                      std::uint16_t{0}, std::uint16_t{0}, std::uint16_t{0}}) {
        detail::append_be16(header, field);
    }
    detail::append_signature(header, "acsp");
    detail::append_be32(header, 0U);
    detail::append_be32(header, 0U);
    detail::append_be32(header, 0U);
    detail::append_be32(header, 0U);
    detail::append_zeros(header, 8U);
    // Header intent is media-relative colorimetric so that a CMS falling back to
    // the header lands on the same intent Windows passes explicitly.
    detail::append_be32(header, 1U);
    detail::append_be32(header, 0x0000F6D6U);
    detail::append_be32(header, 0x00010000U);
    detail::append_be32(header, 0x0000D32DU);
    detail::append_be32(header, 0U);
    detail::append_zeros(header, 16U);
    detail::append_zeros(header, 28U);

    struct TagEntry final {
        std::string_view signature;
        std::vector<std::uint8_t> data;
    };

    std::array<TagEntry, 9> tags{{
        {"desc", detail::text_description(description)},
        {"wtpt", detail::xyz_type(0x0000F6D6U, 0x00010000U, 0x0000D32DU)},
        {"rXYZ", detail::xyz_type(0x00006FA0U, 0x000038F5U, 0x00000390U)},
        {"gXYZ", detail::xyz_type(0x00006297U, 0x0000B787U, 0x000018D9U)},
        {"bXYZ", detail::xyz_type(0x0000249FU, 0x00000F84U, 0x0000B6C3U)},
        {"rTRC", detail::curve_gamma(563U)},
        {"gTRC", detail::curve_gamma(563U)},
        {"bTRC", detail::curve_gamma(563U)},
        {"cprt", detail::text_type(copyright)},
    }};

    const std::size_t table_bytes = 4U + 12U * tags.size();
    std::size_t offset = detail::align4(header.size() + table_bytes);

    std::vector<std::uint8_t> table;
    detail::append_be32(table, static_cast<std::uint32_t>(tags.size()));
    std::vector<std::uint8_t> blob;
    // Each tag owns its own block. Real profiles often share one curve between
    // rTRC/gTRC/bTRC, and sharing would change the bytes, so it is not done here.
    for (const TagEntry& tag : tags) {
        detail::append_signature(table, tag.signature);
        detail::append_be32(table, static_cast<std::uint32_t>(offset));
        detail::append_be32(table, static_cast<std::uint32_t>(tag.data.size()));
        const std::size_t padded = detail::align4(tag.data.size());
        blob.insert(blob.end(), tag.data.begin(), tag.data.end());
        detail::append_zeros(blob, padded - tag.data.size());
        offset += padded;
    }

    std::vector<std::uint8_t> profile;
    profile.reserve(declared_bytes);
    profile.insert(profile.end(), header.begin(), header.end());
    profile.insert(profile.end(), table.begin(), table.end());
    detail::append_zeros(
        profile, detail::align4(header.size() + table_bytes) - (header.size() + table_bytes));
    profile.insert(profile.end(), blob.begin(), blob.end());
    if (profile.size() < declared_bytes) {
        detail::append_zeros(profile, declared_bytes - profile.size());
    }
    return profile;
}

}  // namespace negaflow::fixtures
