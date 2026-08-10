#include "negaflow/color/soft_proof.h"

#include "negaflow/color/icc_profile.h"

#include <algorithm>
#include <cstddef>
#include <optional>

namespace negaflow::color {
namespace {

constexpr std::size_t icc_header_bytes = 128U;
constexpr std::size_t icc_tag_count_bytes = 4U;
constexpr std::size_t icc_tag_record_bytes = 12U;
constexpr std::size_t icc_xyz_type_bytes = 20U;

constexpr std::uint32_t rgb_data_space = 0x52474220U;  // 'RGB '
constexpr std::uint32_t xyz_type_signature = 0x58595A20U;  // 'XYZ '
constexpr std::uint32_t tag_wtpt = 0x77747074U;
constexpr std::uint32_t tag_bkpt = 0x626B7074U;
constexpr std::uint32_t tag_r_xyz = 0x7258595AU;
constexpr std::uint32_t tag_g_xyz = 0x6758595AU;
constexpr std::uint32_t tag_b_xyz = 0x6258595AU;
constexpr std::uint32_t tag_r_trc = 0x72545243U;
constexpr std::uint32_t tag_g_trc = 0x67545243U;
constexpr std::uint32_t tag_b_trc = 0x62545243U;
constexpr std::uint32_t tag_b2a0 = 0x42324130U;

[[nodiscard]] std::uint32_t read_be_u32(
    const std::span<const std::uint8_t> bytes,
    const std::size_t offset) noexcept {
    return (static_cast<std::uint32_t>(bytes[offset]) << 24U) |
           (static_cast<std::uint32_t>(bytes[offset + 1U]) << 16U) |
           (static_cast<std::uint32_t>(bytes[offset + 2U]) << 8U) |
           static_cast<std::uint32_t>(bytes[offset + 3U]);
}

[[nodiscard]] double read_s15_fixed16(
    const std::span<const std::uint8_t> bytes,
    const std::size_t offset) noexcept {
    return static_cast<double>(static_cast<std::int32_t>(read_be_u32(bytes, offset))) /
           65536.0;
}

struct TagLocation final {
    std::uint32_t offset{0U};
    std::uint32_t size{0U};
};

// Only ever called after validate_icc_profile has accepted the bytes, so the tag table is
// known to be in bounds and free of duplicates.
[[nodiscard]] std::optional<TagLocation> find_tag(
    const std::span<const std::uint8_t> bytes,
    const std::uint32_t tag_count,
    const std::uint32_t signature) noexcept {
    for (std::uint32_t index = 0U; index < tag_count; ++index) {
        const std::size_t record = icc_header_bytes + icc_tag_count_bytes +
                                   static_cast<std::size_t>(index) * icc_tag_record_bytes;
        if (read_be_u32(bytes, record) != signature) {
            continue;
        }
        return TagLocation{read_be_u32(bytes, record + 4U), read_be_u32(bytes, record + 8U)};
    }
    return std::nullopt;
}

[[nodiscard]] std::optional<SoftProofXyz> read_xyz_tag(
    const std::span<const std::uint8_t> bytes,
    const std::uint32_t tag_count,
    const std::uint32_t signature) noexcept {
    const std::optional<TagLocation> location = find_tag(bytes, tag_count, signature);
    if (!location.has_value() || location->size < icc_xyz_type_bytes) {
        return std::nullopt;
    }
    const std::size_t offset = location->offset;
    if (read_be_u32(bytes, offset) != xyz_type_signature) {
        return std::nullopt;
    }
    return SoftProofXyz{
        read_s15_fixed16(bytes, offset + 8U),
        read_s15_fixed16(bytes, offset + 12U),
        read_s15_fixed16(bytes, offset + 16U),
    };
}

[[nodiscard]] bool has_matrix_trc_tags(
    const std::span<const std::uint8_t> bytes,
    const std::uint32_t tag_count) noexcept {
    for (const std::uint32_t signature :
         {tag_r_xyz, tag_g_xyz, tag_b_xyz, tag_r_trc, tag_g_trc, tag_b_trc}) {
        if (!find_tag(bytes, tag_count, signature).has_value()) {
            return false;
        }
    }
    return true;
}

// The colorants of a matrix/TRC profile sum to the PCS white, so this recovers the
// D50-relative white regardless of what a v2 `wtpt` happens to declare.
[[nodiscard]] std::optional<SoftProofXyz> colorant_sum_white(
    const std::span<const std::uint8_t> bytes,
    const std::uint32_t tag_count) noexcept {
    const std::optional<SoftProofXyz> red = read_xyz_tag(bytes, tag_count, tag_r_xyz);
    const std::optional<SoftProofXyz> green = read_xyz_tag(bytes, tag_count, tag_g_xyz);
    const std::optional<SoftProofXyz> blue = read_xyz_tag(bytes, tag_count, tag_b_xyz);
    if (!red.has_value() || !green.has_value() || !blue.has_value()) {
        return std::nullopt;
    }
    return SoftProofXyz{
        red->x + green->x + blue->x,
        red->y + green->y + blue->y,
        red->z + green->z + blue->z,
    };
}

[[nodiscard]] double clamp_ratio(
    const double value,
    const double reference,
    const double ceiling) noexcept {
    if (!(reference > 0.0)) {
        return 0.0;
    }
    return std::clamp(value / reference, 0.0, ceiling);
}

// Snapped as a triple rather than per channel: a paper that is neutral in two channels and
// tinted in the third is a real paper and must survive intact.
void snap_to_reference(std::array<double, 3>& channels, const double reference) noexcept {
    for (const double channel : channels) {
        if (std::abs(channel - reference) > soft_proof_neutral_tolerance) {
            return;
        }
    }
    channels = {reference, reference, reference};
}

}  // namespace

SoftProofMedia read_soft_proof_media(const std::span<const std::uint8_t> bytes) noexcept {
    SoftProofMedia media{};
    const IccProfileValidationResult validation = validate_icc_profile(bytes);
    if (validation.status != IccProfileStatus::ok) {
        return media;
    }

    const std::uint32_t tag_count = validation.info.tag_count;
    const bool matrix_trc = validation.info.data_color_space == rgb_data_space &&
                            has_matrix_trc_tags(bytes, tag_count);

    std::optional<SoftProofXyz> white{};
    if (matrix_trc) {
        white = colorant_sum_white(bytes, tag_count);
    }
    if (!white.has_value()) {
        white = read_xyz_tag(bytes, tag_count, tag_wtpt);
    }
    if (white.has_value()) {
        media.has_white = true;
        media.white = *white;
    }

    if (const std::optional<SoftProofXyz> black =
            read_xyz_tag(bytes, tag_count, tag_bkpt);
        black.has_value()) {
        media.has_black = true;
        media.black = *black;
    }
    return media;
}

bool is_rgb_output_profile(const std::span<const std::uint8_t> bytes) noexcept {
    const IccProfileValidationResult validation = validate_icc_profile(bytes);
    if (validation.status != IccProfileStatus::ok ||
        validation.info.data_color_space != rgb_data_space) {
        return false;
    }
    const std::uint32_t tag_count = validation.info.tag_count;
    // Either an invertible matrix/TRC profile or a LUT profile carrying the PCS-to-device
    // table. A scanner profile with only A2B0 fails here, which is the point.
    return has_matrix_trc_tags(bytes, tag_count) ||
           find_tag(bytes, tag_count, tag_b2a0).has_value();
}

SoftProofPaper soft_proof_paper(const SoftProofMedia& media) noexcept {
    SoftProofPaper paper{};
    if (media.has_white) {
        paper.white = {
            clamp_ratio(media.white.x, soft_proof_reference_d50.x,
                        soft_proof_paper_white_ceiling),
            clamp_ratio(media.white.y, soft_proof_reference_d50.y,
                        soft_proof_paper_white_ceiling),
            clamp_ratio(media.white.z, soft_proof_reference_d50.z,
                        soft_proof_paper_white_ceiling),
        };
        snap_to_reference(paper.white, 1.0);
    }
    if (media.has_black) {
        paper.black = {
            clamp_ratio(media.black.x, soft_proof_reference_d50.x,
                        soft_proof_black_ink_ceiling),
            clamp_ratio(media.black.y, soft_proof_reference_d50.y,
                        soft_proof_black_ink_ceiling),
            clamp_ratio(media.black.z, soft_proof_reference_d50.z,
                        soft_proof_black_ink_ceiling),
        };
        snap_to_reference(paper.black, 0.0);
    }
    return paper;
}

SoftProofTransfer soft_proof_transfer(const SoftProofPaper& paper) noexcept {
    SoftProofTransfer transfer{};
    for (std::size_t channel = 0U; channel < 3U; ++channel) {
        // A paper darker than its own ink would invert the frame, so the range collapses
        // to zero instead of going negative.
        transfer.scale[channel] = static_cast<float>(
            std::max(0.0, paper.white[channel] - paper.black[channel]));
        transfer.bias[channel] = static_cast<float>(paper.black[channel]);
    }
    return transfer;
}

}  // namespace negaflow::color
