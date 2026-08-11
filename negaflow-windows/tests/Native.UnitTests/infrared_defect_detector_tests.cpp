#include "negaflow/imaging/infrared_defect_detector.h"

#include <cmath>
#include <cstddef>
#include <cstdint>
#include <iostream>
#include <vector>

namespace {

int failures = 0;

void expect(const bool condition, const char* name) {
    if (!condition) {
        ++failures;
        std::cerr << "FAIL " << name << '\n';
    }
}

void dark_disk(
    std::vector<float>& plane,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::int32_t center_x,
    const std::int32_t center_y,
    const std::int32_t radius,
    const float value) {
    for (std::int32_t y = 0; y < static_cast<std::int32_t>(height); ++y) {
        for (std::int32_t x = 0; x < static_cast<std::int32_t>(width); ++x) {
            const std::int32_t dx = x - center_x;
            const std::int32_t dy = y - center_y;
            if (dx * dx + dy * dy <= radius * radius) {
                plane[static_cast<std::size_t>(y) * width + static_cast<std::uint32_t>(x)] = value;
            }
        }
    }
}

float attenuation_at(
    const negaflow::imaging::InfraredDetection& detection,
    const std::uint32_t x,
    const std::uint32_t y) {
    for (const auto& cluster : detection.clusters) {
        const std::uint32_t y0 = detection.height - cluster.roi_y_up - cluster.height;
        if (x < cluster.roi_x || x >= cluster.roi_x + cluster.width ||
            y < y0 || y >= y0 + cluster.height) continue;
        const std::size_t local = static_cast<std::size_t>(y - y0) * cluster.width + x - cluster.roi_x;
        return static_cast<float>(cluster.attenuation_r16[local]) / 65535.0F;
    }
    return 0.0F;
}

void test_confirmed_partial_occlusion_builds_r16_cluster() {
    constexpr std::uint32_t width = 128U;
    constexpr std::uint32_t height = 96U;
    std::vector<float> infrared(static_cast<std::size_t>(width) * height, 0.8F);
    std::vector<float> red(static_cast<std::size_t>(width) * height, 0.7F);
    dark_disk(infrared, width, height, 62, 48, 4, 0.48F);
    dark_disk(red, width, height, 62, 48, 4, 0.42F);
    negaflow::imaging::InfraredDetectorParameters parameters{};
    parameters.alignment_search_radius = 0;
    const auto result = negaflow::imaging::detect_infrared_defects(
        infrared, red, width, height, parameters);
    expect(result.status == negaflow::imaging::InfraredDetectionStatus::ok,
           "confirmed_status");
    expect(result.detection.candidate_count >= 1U, "candidate_count");
    expect(result.detection.confirmed_count >= 1U, "confirmed_count");
    expect(!result.detection.clusters.empty(), "cluster_present");
    expect(attenuation_at(result.detection, 62U, 48U) > 0.1F,
           "center_attenuation_present");
}

void test_infrared_only_mark_is_rejected() {
    constexpr std::uint32_t width = 128U;
    constexpr std::uint32_t height = 96U;
    std::vector<float> infrared(static_cast<std::size_t>(width) * height, 0.8F);
    std::vector<float> red(static_cast<std::size_t>(width) * height, 0.7F);
    dark_disk(infrared, width, height, 62, 48, 4, 0.48F);
    negaflow::imaging::InfraredDetectorParameters parameters{};
    parameters.alignment_search_radius = 0;
    const auto result = negaflow::imaging::detect_infrared_defects(
        infrared, red, width, height, parameters);
    expect(result.status == negaflow::imaging::InfraredDetectionStatus::no_defects,
           "infrared_only_rejected");
}

void test_global_seed_alignment_places_attenuation_on_visible_defect() {
    constexpr std::uint32_t width = 128U;
    constexpr std::uint32_t height = 96U;
    std::vector<float> infrared(static_cast<std::size_t>(width) * height, 0.8F);
    std::vector<float> red(static_cast<std::size_t>(width) * height, 0.7F);
    dark_disk(infrared, width, height, 67, 45, 5, 0.44F);
    dark_disk(red, width, height, 63, 48, 5, 0.39F);
    negaflow::imaging::InfraredDetectorParameters parameters{};
    parameters.alignment_search_radius = 8;
    const auto result = negaflow::imaging::detect_infrared_defects(
        infrared, red, width, height, parameters);
    expect(result.status == negaflow::imaging::InfraredDetectionStatus::ok,
           "aligned_status");
    expect(result.detection.alignment.status ==
               negaflow::imaging::InfraredAlignmentStatus::aligned,
           "alignment_accepted");
    expect(result.detection.offset_x == 4 && result.detection.offset_y == -3,
           "alignment_offset");
    expect(attenuation_at(result.detection, 63U, 48U) > 0.1F,
           "aligned_attenuation_location");
}

void test_diagonal_scratch_uses_eight_connected_candidates() {
    constexpr std::uint32_t width = 128U;
    constexpr std::uint32_t height = 96U;
    std::vector<float> infrared(static_cast<std::size_t>(width) * height, 0.8F);
    std::vector<float> red(static_cast<std::size_t>(width) * height, 0.7F);
    for (std::uint32_t ordinal = 0U; ordinal < 24U; ++ordinal) {
        infrared[static_cast<std::size_t>(28U + ordinal) * width + 38U + ordinal] = 0.42F;
        red[static_cast<std::size_t>(28U + ordinal) * width + 38U + ordinal] = 0.36F;
    }
    negaflow::imaging::InfraredDetectorParameters parameters{};
    parameters.alignment_search_radius = 0;
    const auto result = negaflow::imaging::detect_infrared_defects(
        infrared, red, width, height, parameters);
    expect(result.status == negaflow::imaging::InfraredDetectionStatus::ok,
           "diagonal_status");
    expect(result.detection.confirmed_count >= 1U, "diagonal_confirmed");
    expect(attenuation_at(result.detection, 49U, 39U) > 0.1F,
           "diagonal_contiguous_attenuation");
}

void test_untrusted_limit_seed_recovers_consensus_offset() {
    constexpr std::uint32_t width = 256U;
    constexpr std::uint32_t height = 160U;
    std::vector<float> infrared(static_cast<std::size_t>(width) * height, 0.8F);
    std::vector<float> red(static_cast<std::size_t>(width) * height, 0.7F);
    for (std::int32_t row = 0; row < 3; ++row) {
        for (std::int32_t column = 0; column < 3; ++column) {
            const std::int32_t visible_x = 48 + column * 62;
            const std::int32_t y = 40 + row * 40;
            dark_disk(red, width, height, visible_x, y, 3, 0.38F);
            dark_disk(infrared, width, height, visible_x + 20, y, 3, 0.44F);
        }
    }
    negaflow::imaging::InfraredDetectorParameters parameters{};
    parameters.alignment_search_radius = 20;
    const auto result = negaflow::imaging::detect_infrared_defects(
        infrared, red, width, height, parameters);
    expect(result.status == negaflow::imaging::InfraredDetectionStatus::ok,
           "consensus_status");
    expect(result.detection.alignment.status ==
               negaflow::imaging::InfraredAlignmentStatus::search_limit_reached,
           "consensus_seed_rejected");
    expect(result.detection.offset_x == -20 && result.detection.offset_y == 0,
           "consensus_offset");
    if (result.detection.offset_x != -20 || result.detection.offset_y != 0) {
        std::cerr << "consensus actual offset " << result.detection.offset_x << ','
                  << result.detection.offset_y << '\n';
    }
    expect(result.detection.confirmed_count >= 8U, "consensus_confirmed_count");
    expect(attenuation_at(result.detection, 48U, 40U) > 0.1F,
           "consensus_target_location");
}

void test_border_connected_margin_dilates_safety_rim() {
    constexpr std::uint32_t width = 128U;
    constexpr std::uint32_t height = 96U;
    std::vector<float> infrared(static_cast<std::size_t>(width) * height, 0.8F);
    std::vector<float> red(static_cast<std::size_t>(width) * height, 0.7F);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < 20U; ++x) {
            const float ir_value = x < 16U ? 0.02F : 0.30F;
            const float red_value = x < 16U ? 0.02F : 0.26F;
            infrared[static_cast<std::size_t>(y) * width + x] = ir_value;
            red[static_cast<std::size_t>(y) * width + x] = red_value;
        }
    }
    negaflow::imaging::InfraredDetectorParameters parameters{};
    parameters.alignment_search_radius = 0;
    const auto result = negaflow::imaging::detect_infrared_defects(
        infrared, red, width, height, parameters);
    expect(result.status == negaflow::imaging::InfraredDetectionStatus::no_defects,
           "margin_halo_rejected");
}

void test_input_contract_and_cancel() {
    std::vector<float> plane(63U * 64U, 0.5F);
    auto result = negaflow::imaging::detect_infrared_defects(plane, plane, 63U, 64U);
    expect(result.status == negaflow::imaging::InfraredDetectionStatus::too_small,
           "too_small");
    std::uint32_t cancelled = 1U;
    plane.assign(64U * 64U, 0.5F);
    result = negaflow::imaging::detect_infrared_defects(
        plane, plane, 64U, 64U, {}, {&cancelled});
    expect(result.status == negaflow::imaging::InfraredDetectionStatus::cancelled,
           "cancelled");
}

void test_macos_anchor_scene_recovers_defect_seed_and_scratch() {
    constexpr std::uint32_t width = 384U;
    constexpr std::uint32_t height = 320U;
    const std::size_t area = static_cast<std::size_t>(width) * height;
    std::vector<float> red(area, 0.0F);
    std::vector<float> aligned(area, 0.0F);
    std::uint64_t state = 20260721ULL;
    auto noise = [&]() {
        state = state * 6364136223846793005ULL + 1442695040888963407ULL;
        return static_cast<float>((state >> 33U) & 0xFFFFU) / 65535.0F - 0.5F;
    };
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            float r = 0.18F + 0.5F * static_cast<float>(x) / static_cast<float>(width);
            if (x >= 192U) r += 0.18F;
            if ((y / 24U) % 2U == 0U) r += 0.08F;
            const float dx = static_cast<float>(x) / static_cast<float>(width) - 0.5F;
            const float dy = static_cast<float>(y) / static_cast<float>(height) - 0.5F;
            const float vignette = 1.0F - 0.10F * (dx * dx + dy * dy) * 4.0F;
            const std::size_t index = static_cast<std::size_t>(y) * width + x;
            red[index] = std::min(1.0F, r * vignette);
            aligned[index] = std::min(
                1.0F,
                (0.84F + 0.08F * std::log(std::max(red[index], 1.0e-4F))) * vignette) +
                0.008F * noise();
        }
    }
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < 28U; ++x) {
            aligned[static_cast<std::size_t>(y) * width + x] = 0.02F;
            red[static_cast<std::size_t>(y) * width + x] = 0.02F;
        }
    }
    const auto occlude = [&](const std::size_t index, const float depth) {
        const float before = aligned[index];
        const float after = std::max(0.0F, before - depth);
        aligned[index] = after;
        red[index] *= before > 1.0e-4F ? after / before : 0.0F;
    };
    const auto spot = [&](const std::int32_t center_x, const std::int32_t center_y,
                          const std::int32_t radius, const float depth) {
        for (std::int32_t y = center_y - radius; y <= center_y + radius; ++y) {
            for (std::int32_t x = center_x - radius; x <= center_x + radius; ++x) {
                const std::int32_t dx = x - center_x;
                const std::int32_t dy = y - center_y;
                if (dx * dx + dy * dy <= radius * radius) {
                    occlude(static_cast<std::size_t>(y) * width + static_cast<std::uint32_t>(x), depth);
                }
            }
        }
    };
    spot(80, 60, 3, 0.35F);
    spot(200, 90, 2, 0.4F);
    spot(310, 50, 4, 0.3F);
    spot(140, 240, 3, 0.35F);
    spot(255, 280, 2, 0.45F);
    for (std::uint32_t y = 40U; y <= 260U; ++y) {
        for (std::uint32_t x = 176U; x <= 177U; ++x) {
            occlude(static_cast<std::size_t>(y) * width + x, 0.3F);
        }
    }
    for (std::uint32_t x = 220U; x <= 340U; ++x) {
        for (std::uint32_t y = 160U; y <= 161U; ++y) {
            occlude(static_cast<std::size_t>(y) * width + x, 0.3F);
        }
    }
    std::vector<float> infrared(area, 0.0F);
    for (std::int32_t y = 0; y < static_cast<std::int32_t>(height); ++y) {
        for (std::int32_t x = 0; x < static_cast<std::int32_t>(width); ++x) {
            const std::int32_t source_x = x - 3;
            const std::int32_t source_y = y - 2;
            if (source_x >= 0 && source_y >= 0) {
                infrared[static_cast<std::size_t>(y) * width + static_cast<std::uint32_t>(x)] =
                    aligned[static_cast<std::size_t>(source_y) * width +
                            static_cast<std::uint32_t>(source_x)];
            }
        }
    }
    negaflow::imaging::InfraredDetectorParameters parameters{};
    parameters.alignment_search_radius = 8;
    parameters.dilate_radius = 2;
    const auto result = negaflow::imaging::detect_infrared_defects(
        infrared, red, width, height, parameters);
    expect(result.status == negaflow::imaging::InfraredDetectionStatus::ok,
           "anchor_status");
    expect(result.detection.offset_x == 3 && result.detection.offset_y == 2,
           "anchor_defect_alignment");
    expect(result.detection.components.size() >= 5U, "anchor_component_count");
    bool has_vertical_scratch = false;
    for (const auto& component : result.detection.components) {
        has_vertical_scratch |= component.classification ==
            negaflow::imaging::InfraredDefectClass::scratch_vertical;
    }
    expect(has_vertical_scratch, "anchor_vertical_scratch");
}

}  // namespace

int main() {
    test_confirmed_partial_occlusion_builds_r16_cluster();
    test_infrared_only_mark_is_rejected();
    test_global_seed_alignment_places_attenuation_on_visible_defect();
    test_diagonal_scratch_uses_eight_connected_candidates();
    test_untrusted_limit_seed_recovers_consensus_offset();
    test_border_connected_margin_dilates_safety_rim();
    test_input_contract_and_cancel();
    test_macos_anchor_scene_recovers_defect_seed_and_scratch();
    if (failures != 0) {
        std::cerr << failures << " infrared detector checks failed\n";
        return 1;
    }
    std::cout << "infrared detector checks passed\n";
    return 0;
}
