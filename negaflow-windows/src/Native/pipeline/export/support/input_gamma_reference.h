#pragma once
#include "export/stages/observe.h"
#include <array>
#include <optional>

namespace negaflow::pipeline::develop_export_detail {
[[nodiscard]] std::optional<DevelopExportOutcome> prepare_input_gamma_reference(
    const DevelopExportRequest& request, const DevelopRunControl& control, const ObservedSource& observed,
    std::optional<std::array<float, 3>>& range) noexcept;
}
