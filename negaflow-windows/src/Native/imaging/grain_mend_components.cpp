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
    const CandidateMaps& candidates,
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
    const CandidateMaps& candidates,
    const std::size_t maximum_dust_area,
    const std::uint32_t minimum_scratch_length,
    const double dust_sensitivity,
    const bool labeled_detection,
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
        ? 12.0 + dust_sensitivity * 12.0
        : 0.0;

    dust.erase(
        std::remove_if(
            dust.begin(),
            dust.end(),
            [&](const Component& component) {
                return !component.has_strong ||
                       (labeled_detection &&
                        static_cast<double>(component.strong_count) /
                                static_cast<double>(component.pixels.size()) <
                            dust_minimum_strong_fraction) ||
                       !passes_dust_gate(
                           component,
                           maximum_dust_area,
                           maximum_dust_aspect,
                           minimum_thick_defect,
                           maximum_thick_defect) ||
                       !is_isolated(component, chunky, image);
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
    const int structure_radius_reference,
    const bool reject_structure_lines,
    std::size_t& accepted_pixels,
    const CandidateMaps* const candidates,
    std::vector<ClassifiedComponent>* const components) {
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
            maximum_dust_area,
            *components);
    }
    return mask;
}

std::vector<std::uint8_t> build_automatic_mask(
    const DetectionImage& image,
    const CandidateMaps& candidates,
    const bool reject_structure_lines,
    std::size_t& accepted_pixels) {
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
        static_cast<int>(std::min(image.width, image.height)),
        reject_structure_lines,
        accepted_pixels);
}


}  // namespace negaflow::imaging::grain_mend_detail
