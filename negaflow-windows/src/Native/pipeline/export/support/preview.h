#pragma once

#include "negaflow/pipeline/develop_export.h"

#include "negaflow/color/soft_proof.h"
#include "negaflow/imaging/grain_mend.h"
#include "negaflow/imaging/image_transform.h"
#include "negaflow/imaging/scanner_to_working.h"

#include <cstddef>
#include <cstdint>

namespace negaflow::pipeline::develop_export_detail {

// GrainMend 단계에서 멈추고 검출 결과만 받아 가는 대상입니다. preview 와 배타적입니다.
struct DetectTarget final {
    std::uint8_t* mask{nullptr};
    std::size_t capacity_bytes{0};
    GrainMendDetectionOutcome* result{nullptr};
    negaflow::imaging::GrainMendRoi roi{};
};

// 게시 대신 호출자 버퍼에 BGRA8 미리보기를 쓴다.
struct PreviewTarget final {
    std::uint32_t maximum_width{0};
    std::uint32_t maximum_height{0};
    std::uint8_t* pixels{nullptr};
    std::size_t capacity_bytes{0};
    negaflow::color::SoftProofTransfer proof{};
    // macOS `clippingOverlayEnabled`. 현상 결과는 안 바꾸고 표시만 얹습니다.
    bool clipping_overlay{false};
};

// macOS `displayProxy` 와 같은 상자 맞춤. 종횡비를 유지하고 긴 변을 먼저 맞춘다.
void preview_fit_size(
    std::uint32_t source_width,
    std::uint32_t source_height,
    std::uint32_t maximum_width,
    std::uint32_t maximum_height,
    std::uint32_t& width,
    std::uint32_t& height) noexcept;

// 작업 화상을 표시용 BGRA8 로 상자 평균 축소해 쓴다. 게시 파일 경로와는 무관하다.
//
// `deferred` 가 있으면 회전·뒤집기·자르기가 **아직 안 걸린** 화상을 받습니다. 상주 GPU
// 인코드가 그 자리 옮김을 함께 처리하므로 호스트 버퍼를 새로 만들지 않습니다. GPU 갈래를
// 못 타면 여기서 CPU `apply_image_transform` 을 걸고 평소 경로로 갑니다 — 결과는 같습니다.
[[nodiscard]] DevelopExportOutcome write_preview(
    const negaflow::imaging::WorkingImage& image,
    const PreviewTarget& target,
    DevelopExportOutcome outcome,
    const negaflow::imaging::ImageTransformGather* deferred = nullptr) noexcept;

}  // namespace negaflow::pipeline::develop_export_detail
