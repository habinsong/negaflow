#pragma once

#include "grain_mend_classifier.h"
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

// `components` 가 null 이 아니면 채택된 컴포넌트를 분류까지 채워 담습니다. 마스크만 필요한
// 호출(브러시 경로 등)은 null 을 넘겨 그 일을 건너뜁니다 — macOS 도 라벨 검출에서만 분류합니다.
// `candidates` 는 분류기가 읽는 국소 통계를 들고 있어야 하며, 없으면 분류를 건너뜁니다.
[[nodiscard]] std::vector<std::uint8_t> build_automatic_mask_from_evidence(
    const DetectionImage& image,
    const std::vector<std::uint8_t>& evidence,
    const std::vector<float>& scratch_response,
    std::size_t maximum_dust_area,
    int structure_radius_reference,
    bool reject_structure_lines,
    std::size_t& accepted_pixels,
    const CandidateMaps* candidates = nullptr,
    std::vector<ClassifiedComponent>* components = nullptr);

[[nodiscard]] std::vector<std::uint8_t> build_automatic_mask(
    const DetectionImage& image,
    const CandidateMaps& candidates,
    bool reject_structure_lines,
    std::size_t& accepted_pixels);

}  // namespace negaflow::imaging::grain_mend_detail
