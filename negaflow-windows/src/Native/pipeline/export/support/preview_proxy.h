#pragma once

#include <cstdint>

#include "export/stages/observe.h"
#include "export/support/preview.h"
#include "export/support/scene_measurement_memo.h"

#include "negaflow/imaging/analysis_region.h"
#include "negaflow/imaging/film_base_measurement.h"
#include "negaflow/pipeline/develop_export.h"

#include <array>
#include <memory>
#include <optional>

namespace negaflow::pipeline::develop_export_detail {

/// macOS `DevelopFrameRenderer.fullMaxDimension` — 정착 프리뷰의 긴 변입니다.
/// 디코드는 요청 상자가 무엇이든 **이 크기로 한 번만** 풉니다.
inline constexpr std::uint32_t preview_full_max_dimension = 3600U;

// macOS `cachedInteractivePreviewRaw` / `cachedSettledPreviewRaw`.
// 디코드·결함 뒤, 반전 전의 linear raw 프록시입니다.
struct PreviewProxyHint final {
    bool image_is_proxy{false};
    bool has_base{false};
    std::array<float, 3> dmin{};
    DevelopBaseSource base_source{DevelopBaseSource::manual};
    bool use_preset_response{false};
    std::array<float, 3> preset_range_factor{};
    std::optional<negaflow::imaging::FilmBaseMeasurementMethod> measurement_method{};
    std::optional<negaflow::imaging::FilmBaseMeasurementDiagnostics> diagnostics{};
    // 베이스를 찾은 측정 영역(크롭)과 그때 화상의 크기입니다. 베이스는 크롭 바깥 띠에서 찾으므로
    // 크롭이 바뀌면 캐시된 베이스는 낡습니다. 크롭은 raw 키에 넣지 않습니다 — 넣으면 크롭을 바꿀
    // 때마다 원본을 다시 디코드합니다. 대신 꺼낼 때 이 값으로 비교해 베이스만 다시 풉니다.
    std::optional<negaflow::imaging::AnalysisRegion> base_region{};
    std::uint32_t base_image_width{0U};
    std::uint32_t base_image_height{0U};
    // 이 프록시(와 같은 항목에서 파생한 프록시)에서 이미 잰 장면 측정. 캐시 항목과 함께 복사돼도
    // 같은 객체를 가리키므로 한 번 잰 값을 모든 요청이 본다. 프록시가 아닌 화상에는 없다.
    std::shared_ptr<SceneMeasurementMemo> scene_memo{};
};

// 같은 파일·관측·상자·베이스 모드이면 작은 raw 를 돌려주고 디코드를 건너뜁니다.
[[nodiscard]] bool preview_proxy_try_take(
    const DevelopExportRequest& request,
    const ObservedSource& observed,
    const PreviewTarget& preview,
    negaflow::imaging::WorkingImage& image,
    PreviewProxyHint& hint) noexcept;

// 필름 베이스는 원본에서 푼 뒤 (macOS 추정은 별도 통계 축소),
// `displayProxy` 와 같이 Lanczos3 로 상자 안에 맞춥니다.
[[nodiscard]] std::optional<DevelopExportOutcome> preview_proxy_materialize(
    const DevelopExportRequest& request,
    const ObservedSource& observed,
    const PreviewTarget& preview,
    negaflow::imaging::WorkingImage& image,
    PreviewProxyHint& hint) noexcept;

// full-resolution cleaned raw를 보존한 채 표시 proxy만 파생합니다.
[[nodiscard]] std::optional<DevelopExportOutcome> preview_proxy_materialize_from_cleaned(
    const DevelopExportRequest& request,
    const ObservedSource& observed,
    const PreviewTarget& preview,
    const negaflow::imaging::WorkingImage& cleaned,
    negaflow::imaging::WorkingImage& image,
    PreviewProxyHint& hint) noexcept;

}  // namespace negaflow::pipeline::develop_export_detail
