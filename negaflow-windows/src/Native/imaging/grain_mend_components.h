#pragma once

#include "grain_mend_detector.h"

#include <cstddef>
#include <cstdint>
#include <vector>

namespace negaflow::imaging::grain_mend_detail {

// Selects accepted, undilated dust/scratch pixels. Bit 0 is dust and bit 1 is
// scratch. Keeping the kinds separate lets full-resolution tiles be stitched
// before the frame-wide structure-line decision.
[[nodiscard]] std::vector<std::uint8_t> build_automatic_evidence(
    const DetectionImage& image,
    const CandidateMaps& candidates,
    std::size_t maximum_dust_area,
    std::uint32_t minimum_scratch_length,
    double dust_sensitivity,
    bool labeled_detection);

void build_automatic_evidence(
    const DetectionImage& image,
    const CandidateMaps& candidates,
    std::size_t maximum_dust_area,
    std::uint32_t minimum_scratch_length,
    double dust_sensitivity,
    bool labeled_detection,
    std::vector<std::uint8_t>& evidence);

[[nodiscard]] std::vector<std::uint8_t> build_automatic_mask_from_evidence(
    const DetectionImage& image,
    const std::vector<std::uint8_t>& evidence,
    const std::vector<float>& scratch_response,
    std::size_t maximum_dust_area,
    int structure_radius_reference,
    bool reject_structure_lines,
    std::size_t& accepted_pixels);

[[nodiscard]] std::vector<std::uint8_t> build_automatic_mask(
    const DetectionImage& image,
    const CandidateMaps& candidates,
    bool reject_structure_lines,
    std::size_t& accepted_pixels);

}  // namespace negaflow::imaging::grain_mend_detail
