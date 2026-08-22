#pragma once

#include "negaflow/pipeline/develop_export.h"

#include "export/stages/invert.h"
#include "export/support/preview.h"
#include "export/support/progress.h"
#include "negaflow/imaging/bw_toning.h"
#include "negaflow/imaging/film_scan_denoise.h"
#include "negaflow/imaging/image_transform.h"
#include "negaflow/imaging/scanner_to_working.h"
#include "negaflow/imaging/local_dodge_burn.h"
#include "negaflow/imaging/texture_stage.h"
#include "negaflow/imaging/working_film_look.h"

#include <optional>

namespace negaflow::pipeline::develop_export_detail {

// GrainMend 이후 게시 직전까지: denoise, dodge, texture, BW, 변환, 리샘플, 샤픈.
struct FinishStageOutput final {
    negaflow::imaging::OutputSharpeningResult sharpening{};
    bool output_resized{false};
    negaflow::imaging::FilmScanDenoiseInfo denoise{};
    negaflow::imaging::LocalDodgeBurnInfo dodge{};
    negaflow::imaging::TextureStageInfo texture{};
    negaflow::imaging::BwToningInfo bw{};
    negaflow::imaging::ImageTransformInfo transform{};
    // 프리뷰에서 회전·뒤집기·자르기를 **발행까지 미뤘다**는 표시입니다.
    //
    // 왜 미루나 — `apply_image_transform` 은 호스트 버퍼를 새로 만듭니다. 그 한 자리
    // 때문에 GPU 상주 사슬이 끊기고, 그러면 발행도 CPU 로 떨어집니다. 실측(frame_12):
    // 자르기가 없는 사진은 33fps 인데 자르기가 있으면 15fps 였습니다.
    //
    // 자리 옮김뿐이라 발행 커널이 읽는 자리만 바꾸면 되고, 결과는 CPU 판과 비트 단위로
    // 같습니다. 기울이기가 있거나 샤픈이 걸려 있으면 미루지 않습니다 — 그때는 순서가
    // 달라져 다른 사진이 됩니다.
    bool transform_deferred{false};
    negaflow::imaging::ImageTransformGather deferred_transform{};
};

[[nodiscard]] std::optional<DevelopExportOutcome> apply_finish_stages(
    const DevelopExportRequest& request,
    const DevelopRunControl& control,
    const PreviewTarget* preview,
    const DetectTarget* detect,
    RunTracker& tracker,
    const InvertStageOutput& invert,
    const negaflow::imaging::WorkingFilmLookInfo& film_look_info,
    negaflow::imaging::WorkingImage grain_image,
    FinishStageOutput& out) noexcept;

} // namespace negaflow::pipeline::develop_export_detail
