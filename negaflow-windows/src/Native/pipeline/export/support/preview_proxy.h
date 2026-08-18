#pragma once

#include "export/stages/observe.h"
#include "export/support/preview.h"

#include "negaflow/pipeline/develop_export.h"

#include <array>
#include <optional>

namespace negaflow::pipeline::develop_export_detail {

// macOS `cachedInteractivePreviewRaw` / `cachedSettledPreviewRaw`.
// 디코드·결함 뒤, 반전 전의 linear raw 프록시입니다.
struct PreviewProxyHint final {
    bool image_is_proxy{false};
    bool has_base{false};
    std::array<float, 3> dmin{};
    DevelopBaseSource base_source{DevelopBaseSource::manual};
    bool use_preset_response{false};
    std::array<float, 3> preset_dmax_normalized{};
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

}  // namespace negaflow::pipeline::develop_export_detail
