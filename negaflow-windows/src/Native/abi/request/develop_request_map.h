#pragma once

#include "negaflow/abi/develop_output.h"
#include "negaflow/abi/develop_result.h"

#include "negaflow/pipeline/develop_export.h"

#include <cstdint>

namespace negaflow::abi::detail {

// C ABI 현상 요청을 파이프라인 요청으로 옮기는 선언입니다.
// 구현은 버전 군별 번역 단위에 있고, 본문은 원래 파일과 같습니다.

[[nodiscard]] bool map_export_format(
    const std::uint32_t value,
    negaflow::pipeline::DevelopExportFormat& format) noexcept;

[[nodiscard]] bool map_film_type(
    const std::uint32_t value,
    negaflow::imaging::NegativeFilmType& film_type) noexcept;

[[nodiscard]] bool map_source_kind(
    const std::uint32_t value,
    negaflow::imaging::DevelopSourceKind& source_kind) noexcept;

[[nodiscard]] bool map_film_polarity(
    const std::uint32_t value,
    negaflow::pipeline::FilmPolarity& polarity) noexcept;

[[nodiscard]] bool map_base_estimation_mode(
    const std::uint32_t value,
    negaflow::pipeline::NegativeBaseEstimationMode& mode) noexcept;

[[nodiscard]] bool map_film_emulation(
    const std::uint32_t value,
    negaflow::imaging::FilmEmulation& emulation) noexcept;

[[nodiscard]] bool map_request(
    const nf_develop_export_request_v1& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v1& result) noexcept;

[[nodiscard]] bool map_request_v2(
    const nf_develop_export_request_v2& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept;

[[nodiscard]] bool map_request_v3(
    const nf_develop_export_request_v3& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept;

[[nodiscard]] bool map_request_v4(
    const nf_develop_export_request_v4& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept;

[[nodiscard]] bool map_point_curve(
    const nf_point_curve_v1& source,
    negaflow::imaging::PointCurve& destination) noexcept;

[[nodiscard]] bool map_request_v5(
    const nf_develop_export_request_v5& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept;

[[nodiscard]] bool map_request_v6(
    const nf_develop_export_request_v6& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept;

[[nodiscard]] bool map_request_v7(
    const nf_develop_export_request_v7& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept;

[[nodiscard]] bool map_request_v8(
    const nf_develop_export_request_v8& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept;

[[nodiscard]] bool map_request_v9(
    const nf_develop_export_request_v9& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept;

[[nodiscard]] bool map_request_v10(
    const nf_develop_export_request_v10& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept;

[[nodiscard]] bool map_request_v11(
    const nf_develop_export_request_v11& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept;

[[nodiscard]] bool valid_flat_range(
    const std::uint32_t offset,
    const std::uint32_t count,
    const std::uint32_t total) noexcept;

[[nodiscard]] bool map_request_v12(
    const nf_develop_export_request_v12& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept;

[[nodiscard]] bool map_request_v13(
    const nf_develop_export_request_v13& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept;

[[nodiscard]] bool map_request_v14(
    const nf_develop_export_request_v14& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept;

[[nodiscard]] bool map_request_v15(
    const nf_develop_export_request_v15& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept;

[[nodiscard]] bool map_request_v16(
    const nf_develop_export_request_v16& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept;

[[nodiscard]] bool map_request_v17(
    const nf_develop_export_request_v17& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept;

void fail_defect_region_request(
    nf_develop_export_result_v2& result,
    const char* const failure_name) noexcept;

[[nodiscard]] bool map_request_v18(
    const nf_develop_export_request_v18& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept;

[[nodiscard]] bool map_request_v19(
    const nf_develop_export_request_v19& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept;

[[nodiscard]] bool map_request_v20(
    const nf_develop_export_request_v20& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept;

[[nodiscard]] bool map_request_v21(
    const nf_develop_export_request_v21& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept;

[[nodiscard]] bool map_request_v24(
    const nf_develop_export_request_v24& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept;

[[nodiscard]] bool map_request_v25(
    const nf_develop_export_request_v25& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept;

[[nodiscard]] bool map_request_v26(
    const nf_develop_export_request_v26& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept;

[[nodiscard]] bool map_request_v27(
    const nf_develop_export_request_v27& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept;

[[nodiscard]] bool map_request_v28(
    const nf_develop_export_request_v28& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept;

[[nodiscard]] bool map_request_v29(
    const nf_develop_export_request_v29& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept;

[[nodiscard]] bool map_request_v30(
    const nf_develop_export_request_v30& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept;

[[nodiscard]] bool map_request_v31(
    const nf_develop_export_request_v31& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept;

[[nodiscard]] bool map_request_v32(
    const nf_develop_export_request_v32& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept;

[[nodiscard]] bool map_request_v33(
    const nf_develop_export_request_v33& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept;

[[nodiscard]] bool map_request_v34(
    const nf_develop_export_request_v34& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept;

[[nodiscard]] bool map_request_v35(
    const nf_develop_export_request_v35& request,
    const bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept;

[[nodiscard]] bool map_request_v37(
    const nf_develop_export_request_v37& request,
    bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept;

[[nodiscard]] bool map_request_v36(
    const nf_develop_export_request_v36& request,
    bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept;

[[nodiscard]] bool map_request_v38(
    const nf_develop_export_request_v38& request,
    bool require_destination,
    negaflow::pipeline::DevelopExportRequest& pipeline_request,
    nf_develop_export_result_v2& result) noexcept;

}  // namespace negaflow::abi::detail
