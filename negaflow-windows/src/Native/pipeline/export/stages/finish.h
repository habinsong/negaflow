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

}  // namespace negaflow::pipeline::develop_export_detail
