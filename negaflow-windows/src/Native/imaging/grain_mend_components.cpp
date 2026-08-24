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
    const bool labeled_detection,
    const bool extended_dust_scales) {
    std::vector<std::uint8_t> evidence{};
    build_automatic_evidence(
        image,
        candidates,
        maximum_dust_area,
        minimum_scratch_length,
        dust_sensitivity,
        labeled_detection,
        extended_dust_scales,
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
    const bool extended_dust_scales,
    std::vector<std::uint8_t>& evidence) {
    const std::size_t count =
        static_cast<std::size_t>(image.width) * image.height;
    std::vector<Component> dust = collect_components(
        image, candidates.weak, candidates.strong, 1U);
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
        ? labeled_maximum_thickness(dust_sensitivity)
        : 0.0;

    // macOS `buildLabeled` 의 `dustTrustedStrong` 유무입니다. 자동은 nil 을 넘기므로
    // `hasTrustedEvidence` 가 항상 거짓이고 아래 두 규칙이 사실상 꺼집니다.
    const std::vector<std::uint8_t>* const trusted =
        extended_dust_scales && candidates.trusted_strong.size() == count
            ? &candidates.trusted_strong
            : nullptr;
    const std::size_t micro_dust_minimum_area = extended_dust_scales
        ? micro_dust_minimum_area_extended
        : micro_dust_minimum_area_default;

    candidates.dust_components_collected += dust.size();
    dust.erase(
        std::remove_if(
            dust.begin(),
            dust.end(),
            [&](const Component& component) {
                // 원거리 통계가 서로를 억제한 밀집 고대비 먼지는 작은 컴포넌트일 때만
                // 절대 대비 증거로 구제합니다 — macOS `compactTrusted`.
                bool has_trusted_evidence = false;
                if (trusted != nullptr) {
                    for (const std::size_t pixel : component.pixels) {
                        if ((*trusted)[pixel] != 0U) {
                            has_trusted_evidence = true;
                            break;
                        }
                    }
                }
                const bool compact_trusted = has_trusted_evidence &&
                    component.pixels.size() <= compact_trusted_maximum_area;
                if (!component.has_strong && !compact_trusted) {
                    ++candidates.dust_dropped_no_strong;
                    return true;
                }
                if (labeled_detection && component.has_strong &&
                    static_cast<double>(component.strong_count) /
                            static_cast<double>(std::max<std::size_t>(
                                1U, component.pixels.size())) <
                        dust_minimum_strong_fraction) {
                    ++candidates.dust_dropped_strong_fraction;
                    return true;
                }
                // 낮은 임계의 micro-only 경로가 새로 만든 1~2px 컴포넌트는 필름 입자와
                // 구분할 증거가 부족하므로 채택하지 않습니다 — macOS `microDustMinArea`.
                const bool component_trusted = component.has_strong
                    ? has_trusted_evidence
                    : compact_trusted;
                if (!component_trusted &&
                    component.pixels.size() < micro_dust_minimum_area) {
                    ++candidates.dust_dropped_gate;
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
        drop_scratch,
        extended_dust_scales
            ? constrained_region_grain_field_small_maximum
            : grain_field_small_component_maximum);

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

    // macOS `detectComponents` 는 타일마다 `buildLabeled`(그레인 필드 1회)만 돌리고
    // stitch 뒤에는 전역 구조선 배제만 한다. 여기서 그레인 필드를 다시 돌리면
    // 타일에서 이미 살아남은 작은 먼지가 한 번 더 떨어진다.
    std::vector<std::uint8_t> drop_dust(dust.size(), 0U);
    std::vector<std::uint8_t> drop_scratch(scratch.size(), 0U);
    if (timings != nullptr) {
        timings->dust_components_raw = dust.size();
        timings->dust_components_after_grain_field = dust.size();
    }
    // macOS `rejectingGlobalStructureLines`: 전역 스크래치가 gridLineMinField(8) 미만이면
    // 격자·연장 배제를 아예 하지 않는다. 적은 선을 구조로 오인하지 않기 위함이다.
    if (reject_structure_lines &&
        scratch.size() >= grid_line_minimum_field) {
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
