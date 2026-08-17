#pragma once

#include "negaflow/pipeline/develop_export.h"

#include "negaflow/color/soft_proof.h"
#include "negaflow/imaging/grain_mend.h"
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
};

// 작업 화상을 표시용 BGRA8 로 상자 평균 축소해 쓴다. 게시 파일 경로와는 무관하다.
[[nodiscard]] DevelopExportOutcome write_preview(
    const negaflow::imaging::WorkingImage& image,
    const PreviewTarget& target,
    DevelopExportOutcome outcome) noexcept;

}  // namespace negaflow::pipeline::develop_export_detail
