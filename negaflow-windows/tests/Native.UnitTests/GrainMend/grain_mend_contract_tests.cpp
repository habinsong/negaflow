#include "grain_mend_test_support.h"

#include "grain_mend_detector.h"
#include "grain_mend_resample.h"
#include "grain_mend_stitch.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <limits>
#include <utility>
#include <vector>

namespace grain_mend_tests {

void test_invalid_inputs_fail_closed() {
    const auto invalid_strength = negaflow::imaging::apply_grain_mend(
        make_clean_image(),
        {std::numeric_limits<double>::quiet_NaN()});
    expect(
        invalid_strength.status ==
                negaflow::imaging::GrainMendStatus::invalid_parameter &&
            invalid_strength.image.pixels.empty(),
        "a non-finite strength fails closed");

    negaflow::imaging::GrainMendParameters invalid_detection{1.0};
    invalid_detection.protect_detail = 1.01;
    const auto invalid_detection_result = negaflow::imaging::apply_grain_mend(
        make_clean_image(),
        invalid_detection);
    expect(
        invalid_detection_result.status ==
                negaflow::imaging::GrainMendStatus::invalid_parameter &&
            invalid_detection_result.image.pixels.empty(),
        "out-of-range detection controls fail closed");

    auto invalid_image = make_clean_image();
    invalid_image.pixels[0].green = std::numeric_limits<float>::infinity();
    const auto invalid_pixels = negaflow::imaging::apply_grain_mend(
        std::move(invalid_image), {1.0});
    expect(
        invalid_pixels.status == negaflow::imaging::GrainMendStatus::kernel_failed &&
            invalid_pixels.info.kernel_status ==
                negaflow::core::KernelStatus::non_finite_input &&
            invalid_pixels.image.pixels.empty(),
        "non-finite pixels fail closed without a partial image");
}

// A latch set before the call must stop detection and hand back nothing, and an untouched
// flag must not change the result at all. The second half is the one that matters: the
// cancel checks sit inside the hot loops, so they are cheap to get wrong.
void test_cancellation_stops_detection_and_keeps_results() {
    std::uint32_t latched = 1U;
    const auto cancelled = negaflow::imaging::apply_grain_mend(
        make_clean_image(),
        {1.0},
        negaflow::core::CancelFlag{&latched});
    expect(
        cancelled.status == negaflow::imaging::GrainMendStatus::cancelled &&
            cancelled.image.pixels.empty(),
        "a latched cancel flag stops GrainMend and discards pixels");

    std::uint32_t idle = 0U;
    const auto baseline = negaflow::imaging::apply_grain_mend(
        make_clean_image(),
        {1.0});
    const auto with_flag = negaflow::imaging::apply_grain_mend(
        make_clean_image(),
        {1.0},
        negaflow::core::CancelFlag{&idle});
    expect(
        baseline.status == negaflow::imaging::GrainMendStatus::ok &&
            with_flag.status == negaflow::imaging::GrainMendStatus::ok &&
            baseline.image.pixels.size() == with_flag.image.pixels.size(),
        "an unlatched flag leaves GrainMend running normally");

    bool identical = baseline.info.repaired_pixels == with_flag.info.repaired_pixels &&
                     baseline.info.candidate_pixels == with_flag.info.candidate_pixels;
    for (std::size_t index = 0U;
         identical && index < baseline.image.pixels.size();
         ++index) {
        identical =
            baseline.image.pixels[index].red == with_flag.image.pixels[index].red &&
            baseline.image.pixels[index].green == with_flag.image.pixels[index].green &&
            baseline.image.pixels[index].blue == with_flag.image.pixels[index].blue &&
            baseline.image.pixels[index].alpha == with_flag.image.pixels[index].alpha;
    }
    expect(identical, "passing a flag does not change a single repaired pixel");

    // The whole-frame tiled path has its own loop and its own poll point.
    negaflow::imaging::GrainMendParameters tiled{1.0};
    tiled.reject_structure_lines = true;
    const auto cancelled_tiles = negaflow::imaging::apply_grain_mend(
        make_clean_image(),
        tiled,
        negaflow::core::CancelFlag{&latched});
    expect(
        cancelled_tiles.status == negaflow::imaging::GrainMendStatus::cancelled &&
            cancelled_tiles.image.pixels.empty(),
        "the whole-frame tiled path honours the same flag");
}

// 검토 가능한 GrainMend 도구(자동·가이드)는 자동 수리와 **같은 판정**을 보여 주어야 합니다.
// 그래서 검출만 떼어 낸 함수가 수리 경로와 같은 화소 수를 고르는지 봅니다 — 두 벌로 갈라지면
// 사용자가 미리 본 것과 실제로 고쳐진 것이 달라집니다.
void test_detection_only_agrees_with_the_repair_path() {
    auto damaged = make_clean_image();
    damaged.pixels[24U * damaged.width + 18U] = {0.95F, 0.95F, 0.95F, 1.0F};
    for (std::uint32_t y = 14U; y < 58U; ++y) {
        damaged.pixels[static_cast<std::size_t>(y) * damaged.width + 62U] =
            {0.02F, 0.02F, 0.02F, 1.0F};
    }

    negaflow::imaging::GrainMendParameters parameters{1.0};
    // 자동 검토와 자동 복원은 같은 타일·라벨 경로를 쓴다(macOS detectComponents).
    parameters.reject_structure_lines = true;
    const auto detected =
        negaflow::imaging::detect_grain_mend(damaged, parameters);
    const auto repaired =
        negaflow::imaging::apply_grain_mend(damaged, parameters);

    expect(
        detected.status == negaflow::imaging::GrainMendStatus::ok,
        "detection only reports ok on a valid frame");
    expect(
        detected.width == repaired.info.detection_width &&
            detected.height == repaired.info.detection_height,
        "detection only reports the same capped analysis size as the repair");
    if (detected.accepted_pixels != repaired.info.candidate_pixels) {
        std::cerr << "diagnostic detect_vs_repair detect="
                  << detected.accepted_pixels << " repair="
                  << repaired.info.candidate_pixels
                  << " detect_w=" << detected.width
                  << " repair_w=" << repaired.info.detection_width
                  << " detect_components=" << detected.components.size()
                  << '\n';
    }
    expect(
        detected.accepted_pixels == repaired.info.candidate_pixels &&
            detected.accepted_pixels != 0U,
        "detection only accepts exactly the pixels the repair would touch");
    expect(
        detected.mask.size() ==
            static_cast<std::size_t>(detected.width) * detected.height,
        "the mask covers the analysis image one byte per pixel");

    std::size_t marked = 0U;
    for (const std::uint8_t value : detected.mask) {
        if (value != 0U) {
            ++marked;
        }
    }
    expect(marked == detected.accepted_pixels,
        "the reported count matches the marked pixels");

    // 세기는 검출에 영향을 주지 않아야 합니다 — 아직 아무것도 걸지 않은 프레임에서도
    // 자동 버튼이 무엇을 찾았는지 보여 줄 수 있어야 합니다.
    negaflow::imaging::GrainMendParameters idle = parameters;
    idle.strength = 0.0;
    const auto at_zero = negaflow::imaging::detect_grain_mend(damaged, idle);
    expect(
        at_zero.status == negaflow::imaging::GrainMendStatus::ok &&
            at_zero.accepted_pixels == detected.accepted_pixels,
        "strength does not change what detection finds");

    negaflow::imaging::WorkingImage empty{};
    expect(
        negaflow::imaging::detect_grain_mend(empty, parameters).status ==
            negaflow::imaging::GrainMendStatus::invalid_parameter,
        "detection only fails closed on an empty image");
}

// 가이드는 전체에서 찾은 뒤 숨기는 방식이 아니라 선택한 raw ROI만 잘라 분석해야 합니다.
// 이 계약은 주변 통계와 검출 이미지의 크기를 모두 바꾸므로, 반환 좌표도 함께 고정합니다.
void test_guided_detection_crops_to_the_selected_roi() {
    const auto source = make_clean_image();
    const negaflow::imaging::GrainMendRoi roi{0.25, 0.25, 0.5, 0.5};
    const auto detected = negaflow::imaging::detect_grain_mend(
        source, {1.0}, roi);

    expect(
        detected.status == negaflow::imaging::GrainMendStatus::ok &&
            detected.roi_x == 24U && detected.roi_y == 18U &&
            detected.roi_width == 48U && detected.roi_height == 36U,
        "guided detection reports the selected source rectangle");
    expect(
        detected.width == 48U && detected.height == 36U &&
            detected.mask.size() == 48U * 36U,
        "guided detection analyses only the selected rectangle");
}

// macOS의 추가 미세 입자 패스는 기존 결함 후보를 약화시키지 않고, 세 채널에 같이 어두운
// 2~7px 표면 이물만 선택적으로 더합니다. 토글을 끄면 이전 검출 마스크가 정확히 남아야 합니다.
void test_isolated_dark_blob_is_classified_dust_or_pinhole() {
    constexpr std::uint32_t width = 256U;
    constexpr std::uint32_t height = 256U;
    auto damaged = make_uniform_image(width, height, 0.20F);
    for (std::uint32_t y = 80U; y < 92U; ++y) {
        for (std::uint32_t x = 80U; x < 92U; ++x) {
            auto& pixel =
                damaged.pixels[static_cast<std::size_t>(y) * width + x];
            pixel.red = 0.02F;
            pixel.green = 0.02F;
            pixel.blue = 0.02F;
        }
    }

    negaflow::imaging::GrainMendParameters parameters{1.0};
    parameters.dust_sensitivity = 1.0;
    parameters.scratch_sensitivity = 1.0;
    parameters.protect_detail = 0.6;
    parameters.reject_structure_lines = true;
    parameters.detect_micro_specks = false;
    const auto detected = negaflow::imaging::detect_grain_mend(damaged, parameters);
    std::size_t dust_like = 0U;
    for (const auto& component : detected.components) {
        if (component.classification ==
                negaflow::imaging::grain_mend_detail::DefectClassification::dust ||
            component.classification ==
                negaflow::imaging::grain_mend_detail::DefectClassification::
                    pinhole) {
            ++dust_like;
        }
    }
    expect(detected.status == negaflow::imaging::GrainMendStatus::ok,
           "isolated dark blob detection completes");
    expect(dust_like > 0U,
           "detect_grain_mend classifies an isolated dark blob as dust or pinhole");
}

void test_micro_specks_become_classified_components() {
    constexpr std::uint32_t width = 256U;
    constexpr std::uint32_t height = 256U;
    auto damaged = make_uniform_image(width, height, 0.20F);
    std::vector<std::pair<std::uint32_t, std::uint32_t>> specks{};
    for (std::uint32_t x = 40U; x <= 200U; x += 80U) {
        for (std::uint32_t y = 40U; y <= 200U; y += 80U) {
            specks.push_back({x, y});
            add_dark_micro_speck(damaged, x, y, 3U, 0.065F);
        }
    }

    negaflow::imaging::GrainMendParameters off{1.0};
    off.dust_sensitivity = 0.6;
    off.scratch_sensitivity = 0.7;
    off.protect_detail = 0.6;
    off.detect_micro_specks = false;
    const auto legacy = negaflow::imaging::detect_grain_mend(damaged, off);
    negaflow::imaging::GrainMendParameters on = off;
    on.detect_micro_specks = true;
    const auto detected = negaflow::imaging::detect_grain_mend(damaged, on);

    std::size_t classified = 0U;
    for (const auto& component : detected.components) {
        if (component.classification ==
            negaflow::imaging::grain_mend_detail::DefectClassification::
                micro_speck) {
            ++classified;
        }
    }
    std::size_t planted_classified = 0U;
    for (const auto [x, y] : specks) {
        const std::size_t center =
            static_cast<std::size_t>(y + 1U) * width + x + 1U;
        for (const auto& component : detected.components) {
            if (component.classification !=
                negaflow::imaging::grain_mend_detail::DefectClassification::
                    micro_speck) {
                continue;
            }
            if (std::find(component.pixels.begin(), component.pixels.end(),
                          center) != component.pixels.end()) {
                ++planted_classified;
                break;
            }
        }
    }
    if (classified == 0U || planted_classified == 0U) {
        std::cerr << "diagnostic classify_specks classified=" << classified
                  << " planted=" << planted_classified << "/" << specks.size()
                  << " legacy=" << legacy.accepted_pixels
                  << " enabled=" << detected.accepted_pixels
                  << " components=" << detected.components.size() << '\n';
    }
    expect(legacy.status == negaflow::imaging::GrainMendStatus::ok &&
               detected.status == negaflow::imaging::GrainMendStatus::ok,
           "micro-speck classification probe completes");
    expect(classified > 0U && planted_classified > 0U,
           "detect_grain_mend promotes planted specks to MicroSpeck components");
}

void test_micro_speck_detection_is_optional_and_additive() {
    constexpr std::uint32_t width = 512U;
    constexpr std::uint32_t height = 512U;
    auto damaged = make_uniform_image(width, height, 0.20F);
    add_chromatic_grain(damaged, 7U, 50U, 0.015F);
    std::vector<std::pair<std::uint32_t, std::uint32_t>> specks{};
    for (std::uint32_t x = 40U; x <= 400U; x += 60U) {
        for (std::uint32_t y = 60U; y <= 420U; y += 90U) {
            specks.push_back({x, y});
            add_dark_micro_speck(damaged, x, y, 3U, 0.065F);
        }
    }

    negaflow::imaging::GrainMendParameters off{1.0};
    off.dust_sensitivity = 0.6;
    off.scratch_sensitivity = 0.7;
    off.protect_detail = 0.6;
    off.detect_micro_specks = false;
    const auto legacy = negaflow::imaging::detect_grain_mend(damaged, off);
    negaflow::imaging::GrainMendParameters on = off;
    on.detect_micro_specks = true;
    const auto detected = negaflow::imaging::detect_grain_mend(damaged, on);

    expect(
        legacy.status == negaflow::imaging::GrainMendStatus::ok &&
            detected.status == negaflow::imaging::GrainMendStatus::ok,
        "micro-speck detection completes for both toggle states");
    expect(
        detected.accepted_pixels >= legacy.accepted_pixels &&
            detected.mask.size() == legacy.mask.size(),
        "the enabled micro-speck pass only adds to the legacy proposal");
    bool preserves_legacy = true;
    for (std::size_t index = 0U; index < legacy.mask.size(); ++index) {
        preserves_legacy = preserves_legacy &&
            (legacy.mask[index] == 0U || detected.mask[index] != 0U);
    }
    expect(preserves_legacy,
        "the enabled micro-speck pass never removes a legacy candidate");

    std::size_t found = 0U;
    for (const auto [x, y] : specks) {
        const std::size_t center = static_cast<std::size_t>(y + 1U) * width + x + 1U;
        if (detected.mask[center] != 0U) {
            ++found;
        }
    }
    if (found < specks.size()) {
        std::cerr << "diagnostic micro_found=" << found << "/" << specks.size()
                  << " legacy=" << legacy.accepted_pixels
                  << " enabled=" << detected.accepted_pixels << '\n';
    }
    expect(found == specks.size(),
        "the optional micro-speck pass finds every neutral 3px speck on chromatic grain");

    std::size_t classified_micro_specks = 0U;
    std::size_t classified_when_off = 0U;
    for (const auto& component : detected.components) {
        if (component.classification ==
            negaflow::imaging::grain_mend_detail::DefectClassification::micro_speck) {
            ++classified_micro_specks;
        }
    }
    for (const auto& component : legacy.components) {
        if (component.classification ==
            negaflow::imaging::grain_mend_detail::DefectClassification::micro_speck) {
            ++classified_when_off;
        }
    }
    expect(classified_when_off == 0U,
        "disabling the micro-speck pass leaves no MicroSpeck components");
    std::size_t added_centers = 0U;
    std::size_t added_classified = 0U;
    for (const auto [x, y] : specks) {
        const std::size_t center =
            static_cast<std::size_t>(y + 1U) * width + x + 1U;
        if (legacy.mask[center] != 0U || detected.mask[center] == 0U) {
            continue;
        }
        ++added_centers;
        for (const auto& component : detected.components) {
            if (component.classification !=
                negaflow::imaging::grain_mend_detail::DefectClassification::
                    micro_speck) {
                continue;
            }
            if (std::find(component.pixels.begin(), component.pixels.end(),
                          center) != component.pixels.end()) {
                ++added_classified;
                break;
            }
        }
    }
    expect(
        added_centers == 0U || added_classified == added_centers,
        "specks added only by the micro-speck pass are classified MicroSpeck");
}


}  // namespace grain_mend_tests
