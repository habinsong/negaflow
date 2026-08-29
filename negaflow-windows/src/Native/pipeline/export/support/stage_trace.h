#pragma once

// 단계 경계 화소 추적기입니다. 미리보기와 내보내기가 **같은 요청에서 다른 그림**을
// 내놓을 때, 어느 단계에서 갈렸는지는 결과물만 봐서는 알 수 없습니다. 각 단계가 끝난
// 자리에서 평균·최소·최대를 찍어 두면 갈린 지점이 한 줄로 드러납니다.
//
// 환경변수 `NEGAFLOW_STAGE_TRACE=1` 일 때만 켜집니다. 꺼져 있으면 함수 하나가
// 즉시 돌아오고 화소를 건드리지 않습니다.

#include <cstdint>
#include <string>
#include <string_view>

#include "export/stages/grain.h"
#include "export/stages/invert.h"
#include "negaflow/imaging/scanner_to_working.h"
#include "negaflow/pipeline/defect_recipe_stage.h"

namespace negaflow::pipeline::develop_export_detail {

[[nodiscard]] bool stage_trace_enabled() noexcept;

// 실행 한 건의 머리글을 적습니다. 미리보기·검출·내보내기 중 어느 길인지는 넘겨받은
// 대상 포인터가 정합니다 — 구동부가 같은 판정을 두 번 적지 않도록 여기서 가립니다.
void stage_trace_begin(
    const DevelopExportRequest& request,
    const PreviewTarget* preview,
    const DetectTarget* detect) noexcept;

// 단계가 끝난 자리의 화소 통계를 적습니다. GPU 에 머문 화소는 먼저 내립니다.
void stage_trace_image(
    std::string_view stage,
    const negaflow::imaging::WorkingImage& image) noexcept;

// 화소가 아닌 값을 적습니다. 서식은 여기에 둡니다 — 구동부가 진단 문자열을 조립하면
// 그 파일이 파이프라인이 아니라 로깅으로 불어납니다.
void stage_trace_note(std::string_view stage, std::string_view note) noexcept;

// 반전에 실제로 들어간 수치입니다. 필름 베이스가 어디서 왔고 어떤 dmin 이 걸렸는지가
// "왜 이 그림이 이렇게 나왔나" 의 첫 물음입니다.
void stage_trace_invert(const InvertStageOutput& invert) noexcept;

// 결함 레시피가 몇 건 실제로 걸렸는지입니다. 미리보기와 내보내기가 같은 수를 적어야
// 화면과 파일이 같은 그림입니다.
void stage_trace_defect(
    const DevelopExportRequest& request,
    const DefectRecipeStageResult& defect_recipe) noexcept;

void stage_trace_grain_mend(const GrainStageOutput& grain) noexcept;

} // namespace negaflow::pipeline::develop_export_detail
