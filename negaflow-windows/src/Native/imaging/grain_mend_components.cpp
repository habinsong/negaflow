#include "grain_mend_components.h"

#include "grain_mend_component_classification.h"
#include "grain_mend_component_gates.h"
#include "grain_mend_component_types.h"
#include "grain_mend_grain_field.h"
#include "grain_mend_mask_paint.h"
#include "grain_mend_shape.h"
#include "grain_mend_structure_lines.h"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <new>
#include <vector>

namespace negaflow::imaging::grain_mend_detail {

// 조율값은 grain_mend_component_types.h 의 한 표에서만 옵니다.
using namespace tuning;

std::vector<std::uint8_t> build_automatic_evidence(
    const DetectionImage& image,
    CandidateMaps& candidates,
    const std::size_t maximum_dust_area,
    const std::uint32_t minimum_scratch_length,
    const double dust_sensitivity,
    const bool labeled_detection) {
    std::vector<std::uint8_t> evidence{};
    build_automatic_evidence(
        image,
        candidates,
        maximum_dust_area,
        minimum_scratch_length,
        dust_sensitivity,
        labeled_detection,
        evidence);
    return evidence;
}

void build_automatic_evidence(
    const DetectionImage& image,
    CandidateMaps& candidates,
    const std::size_t maximum_dust_area,
    const std::uint32_t minimum_scratch_length,
    const double dust_sensitivity,
    const bool labeled_detection,
    std::vector<std::uint8_t>& evidence) {
    const std::size_t count =
        static_cast<std::size_t>(image.width) * image.height;
    // 측정: 이 스캔에서 dustMag 평균 0.128 ≥ strongMag 0.12 라 weak 가 그레인
    // 카펫이 된다(프레임당 weak 740만). Swift 주석의 전제("그레인은 ≪ strongMag")가
    // 깨진 상태다. 카펫에서 8-연결하면 코어 2434px 가 32개 거대 성분에 녹아 8%
    // 게이트에서 전멸한다. 채택은 hard 코어(SNR 또는 far 게이트를 통과한 strong)
    // 만 연결한다 — macOS 가 strong 없는 weak 성분을 버리는 것과 같은 채택 집합의
    // 코어다. 가장자리 프린지는 카펫이라 붙이지 않는다.
    std::vector<Component> dust = collect_components(
        image,
        labeled_detection ? candidates.strong : candidates.weak,
        candidates.strong,
        1U);
    std::vector<Component> scratch = collect_components(
        image, candidates.weak, candidates.strong, 2U);
    const std::vector<std::uint8_t> chunky = make_chunky_map(dust, count);
    const double maximum_dust_aspect = labeled_detection
        ? 4.0 + dust_sensitivity * 4.0
        : maximum_automatic_dust_aspect;
    const double minimum_scratch_aspect = labeled_detection
        ? 2.5 - dust_sensitivity * 0.7
        : minimum_automatic_scratch_aspect;
    const double minimum_thick_defect = labeled_detection ? 4.0 : 1.0;
    const double maximum_thick_defect = labeled_detection
        ? 12.0 + dust_sensitivity * 12.0
        : 0.0;

    candidates.dust_components_collected += dust.size();
    dust.erase(
        std::remove_if(
            dust.begin(),
            dust.end(),
            [&](const Component& component) {
                if (!component.has_strong) {
                    ++candidates.dust_dropped_no_strong;
                    return true;
                }
                if (labeled_detection &&
                    static_cast<double>(component.strong_count) /
                            static_cast<double>(component.pixels.size()) <
                        dust_minimum_strong_fraction) {
                    ++candidates.dust_dropped_strong_fraction;
                    return true;
                }
                if (!passes_dust_gate(
                        component,
                        maximum_dust_area,
                        maximum_dust_aspect,
                        minimum_thick_defect,
                        maximum_thick_defect)) {
                    ++candidates.dust_dropped_gate;
                    return true;
                }
                if (!is_isolated(component, chunky, image)) {
                    ++candidates.dust_dropped_isolation;
                    return true;
                }
                ++candidates.dust_kept;
                return false;
            }),
        dust.end());
    scratch.erase(
        std::remove_if(
            scratch.begin(),
            scratch.end(),
            [&](const Component& component) {
                if (!passes_scratch_gate(
                        component,
                        image.width,
                        minimum_scratch_length,
                        minimum_scratch_aspect)) {
                    return true;
                }
                if (!labeled_detection || component.has_strong) {
                    return false;
                }
                const PcaMetrics metrics = pca_metrics(
                    component, image.width);
                return metrics.length < weak_geometry_minimum_length ||
                       metrics.thickness > weak_geometry_maximum_thickness ||
                       metrics.aspect < weak_geometry_minimum_aspect;
            }),
        scratch.end());

    std::vector<std::uint8_t> drop_dust(dust.size(), 0U);
    std::vector<std::uint8_t> drop_scratch(scratch.size(), 0U);
    mark_grain_field_drops(
        dust,
        scratch,
        image.width,
        drop_dust,
        drop_scratch);

    evidence.resize(count);
    std::fill(
        evidence.begin(),
        evidence.end(),
        static_cast<std::uint8_t>(0U));
    for (std::size_t index = 0U; index < dust.size(); ++index) {
        if (drop_dust[index] == 0U) {
            for (const std::size_t pixel : dust[index].pixels) {
                evidence[pixel] |= 1U;
            }
        }
    }
    for (std::size_t index = 0U; index < scratch.size(); ++index) {
        if (drop_scratch[index] == 0U) {
            for (const std::size_t pixel : scratch[index].pixels) {
                evidence[pixel] |= 2U;
            }
        }
    }
}

std::vector<std::uint8_t> build_automatic_mask_from_evidence(
    const DetectionImage& image,
    const std::vector<std::uint8_t>& evidence,
    const std::vector<float>& scratch_response,
    const std::size_t maximum_dust_area,
    const std::size_t classification_dust_area,
    const int structure_radius_reference,
    const bool reject_structure_lines,
    std::size_t& accepted_pixels,
    const CandidateMaps* const candidates,
    std::vector<ClassifiedComponent>* const components,
    negaflow::imaging::GrainMendTimings* const timings) {
    const std::size_t count =
        static_cast<std::size_t>(image.width) * image.height;
    if (evidence.size() != count) {
        throw std::bad_alloc{};
    }
    std::vector<Component> dust = collect_components(
        image, evidence, evidence, 1U);
    std::vector<Component> scratch = collect_components(
        image, evidence, evidence, 2U);

    std::vector<std::uint8_t> drop_dust(dust.size(), 0U);
    std::vector<std::uint8_t> drop_scratch(scratch.size(), 0U);
    mark_grain_field_drops(
        dust,
        scratch,
        image.width,
        drop_dust,
        drop_scratch);
    if (timings != nullptr) {
        timings->dust_components_raw = dust.size();
        timings->dust_components_after_grain_field = 0U;
        for (const std::uint8_t drop : drop_dust) {
            if (drop == 0U) {
                ++timings->dust_components_after_grain_field;
            }
        }
    }
    if (reject_structure_lines) {
        const std::vector<std::uint8_t> grid_drops =
            structure_grid_drops(scratch, image, structure_radius_reference);
        const std::vector<std::uint8_t> line_drops = continuation_drops(
            scratch,
            image,
            scratch_response);
        for (std::size_t index = 0U; index < drop_scratch.size(); ++index) {
            drop_scratch[index] = static_cast<std::uint8_t>(
                drop_scratch[index] | grid_drops[index] | line_drops[index]);
        }
    }

    std::vector<std::uint8_t> mask(count, 0U);
    for (std::size_t index = 0U; index < dust.size(); ++index) {
        if (drop_dust[index] != 0U) {
            continue;
        }
        paint_component(dust[index], 0, image, mask);
        fill_interior_holes(
            dust[index], image, maximum_dust_area, mask);
    }
    for (std::size_t index = 0U; index < scratch.size(); ++index) {
        if (drop_scratch[index] == 0U) {
            paint_component(scratch[index], 1, image, mask);
        }
    }
    accepted_pixels = static_cast<std::size_t>(std::count(
        mask.begin(), mask.end(), static_cast<std::uint8_t>(1U)));
    if (components != nullptr) {
        collect_classified(
            dust,
            drop_dust,
            scratch,
            drop_scratch,
            image,
            candidates,
            classification_dust_area,
            *components);
    }
    return mask;
}

std::vector<std::uint8_t> build_automatic_mask(
    const DetectionImage& image,
    CandidateMaps& candidates,
    const bool reject_structure_lines,
    std::size_t& accepted_pixels,
    std::vector<ClassifiedComponent>* const components) {
    const std::uint32_t minimum_scratch_length =
        std::max(10U, image.width / 120U);
    const std::vector<std::uint8_t> evidence = build_automatic_evidence(
        image,
        candidates,
        maximum_automatic_dust_area,
        minimum_scratch_length,
        0.0,
        false);
    return build_automatic_mask_from_evidence(
        image,
        evidence,
        candidates.scratch_response,
        maximum_automatic_dust_area,
        maximum_automatic_dust_area,
        static_cast<int>(std::min(image.width, image.height)),
        reject_structure_lines,
        accepted_pixels,
        &candidates,
        components);
}


}  // namespace negaflow::imaging::grain_mend_detail
