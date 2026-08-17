#pragma once

#include "negaflow/imaging/grain_mend.h"
#include "negaflow/imaging/grain_mend_classifier.h"
#include "grain_mend_detector.h"

#include <cstddef>
#include <cstdint>
#include <vector>

namespace negaflow::imaging::grain_mend_detail {

// Selects accepted, undilated dust/scratch pixels. Bit 0 is dust and bit 1 is
// scratch. Keeping the kinds separate lets full-resolution tiles be stitched
// before the frame-wide structure-line decision.
// `extended_dust_scales` 는 macOS `detectLabeled` 이 `buildLabeled` 로 넘기는 세 인자를
// 한꺼번에 가릅니다: `dustTrustedStrong`(nil ↔ 맵), `microDustMinArea`(1 ↔ 3),
// `grainFieldSmallMax`(12 ↔ 4). 가이드(부분 ROI)에서만 참입니다.
[[nodiscard]] std::vector<std::uint8_t> build_automatic_evidence(
    const DetectionImage& image,
    CandidateMaps& candidates,
    std::size_t maximum_dust_area,
    std::uint32_t minimum_scratch_length,
    double dust_sensitivity,
    bool labeled_detection,
    bool extended_dust_scales = false);

void build_automatic_evidence(
    const DetectionImage& image,
    CandidateMaps& candidates,
    std::size_t maximum_dust_area,
    std::uint32_t minimum_scratch_length,
    double dust_sensitivity,
    bool labeled_detection,
    bool extended_dust_scales,
    std::vector<std::uint8_t>& evidence);

// `components` 가 null 이 아니면 채택된 컴포넌트를 분류까지 채워 담습니다. 마스크만 필요한
// 호출(브러시 경로 등)은 null 을 넘겨 그 일을 건너뜁니다 — macOS 도 라벨 검출에서만 분류합니다.
// `candidates` 는 분류기가 읽는 국소 통계를 들고 있어야 하며, 없으면 분류를 건너뜁니다.
// `classification_dust_area` 는 분류 임계 전용입니다. macOS 도 큰 이물 검출 허용치를 그대로
// pinhole/emulsion 분류에 쓰지 않습니다 — 재사용하면 같은 컴포넌트가 단순 먼지로 재분류됩니다.
[[nodiscard]] std::vector<std::uint8_t> build_automatic_mask_from_evidence(
    const DetectionImage& image,
    const std::vector<std::uint8_t>& evidence,
    const std::vector<float>& scratch_response,
    std::size_t maximum_dust_area,
    std::size_t classification_dust_area,
    int structure_radius_reference,
    bool reject_structure_lines,
    std::size_t& accepted_pixels,
    const CandidateMaps* candidates = nullptr,
    std::vector<ClassifiedComponent>* components = nullptr,
    negaflow::imaging::GrainMendTimings* timings = nullptr);

// `components` 가 null 이 아니면 채택된 결함을 분류까지 담아 냅니다.
[[nodiscard]] std::vector<std::uint8_t> build_automatic_mask(
    const DetectionImage& image,
    CandidateMaps& candidates,
    bool reject_structure_lines,
    std::size_t& accepted_pixels,
    std::vector<ClassifiedComponent>* components = nullptr);

}  // namespace negaflow::imaging::grain_mend_detail
