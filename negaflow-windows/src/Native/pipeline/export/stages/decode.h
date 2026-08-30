#pragma once

#include "negaflow/pipeline/develop_export.h"

#include "export/stages/observe.h"
#include "export/support/preview.h"
#include "export/support/progress.h"
#include "negaflow/imaging/scanner_to_working.h"

#include <optional>
#include <memory>
#include <stop_token>

namespace negaflow::pipeline::develop_export_detail {

// TIFF 는 스캐너 경로, 그 외는 WIC 표준 화상. 디코드 직후 파일이 바뀌었는지도 확인한다.
[[nodiscard]] std::optional<DevelopExportOutcome> decode_source(
    const DevelopExportRequest& request,
    RunTracker& tracker,
    std::stop_source& stop,
    const ObservedSource& observed,
    negaflow::imaging::WorkingImage& image,
    const PreviewTarget* preview = nullptr) noexcept;

// 판에 놓을 크기로 줄입니다. 0 이면 그대로 둡니다.
//
// 결함 편집이 있는 프레임은 디코드 자리가 아니라 결함을 다 지운 뒤에 이것을 부릅니다.
// 마스크가 원본 화소 좌표라 먼저 줄이면 어긋납니다.
void shrink_to_proxy_long_edge(
    negaflow::imaging::WorkingImage& image,
    std::uint32_t proxy_long_edge) noexcept;

// 디코드 상주 캐시(macOS `residentCleanedRawIDs`). 시험이 비우고 재는 자리입니다.
void decoded_source_store_reset() noexcept;

[[nodiscard]] std::uint64_t decoded_source_store_resident_bytes() noexcept;

// 같은 source observation과 ordered recipe SHA의 full-resolution cleaned raw입니다.
// 프리뷰 크기별 proxy와 달리 interactive/settled가 한 결과를 공유합니다.
[[nodiscard]] bool decoded_cleaned_raw_try_take(
    const std::filesystem::path& path,
    const negaflow::imageio::ImageFileObservation& observation,
    const std::array<std::uint8_t, 32U>& recipe_sha256,
    std::shared_ptr<const negaflow::imaging::WorkingImage>& image,
    DefectRecipeStageInfo& info) noexcept;

void decoded_cleaned_raw_put(
    const std::filesystem::path& path,
    const negaflow::imageio::ImageFileObservation& observation,
    const std::array<std::uint8_t, 32U>& recipe_sha256,
    std::shared_ptr<const negaflow::imaging::WorkingImage> image,
    const DefectRecipeStageInfo& info) noexcept;

}  // namespace negaflow::pipeline::develop_export_detail
