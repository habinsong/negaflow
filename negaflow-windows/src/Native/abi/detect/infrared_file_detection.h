#pragma once

#include "negaflow/imaging/infrared_defect_detector.h"
#include "negaflow/color/input_gamma_profile.h"

#include <filesystem>

namespace negaflow::abi::detail {

enum class InfraredVisibleSourceKind {
    infer_from_extension,
    scanner_tiff,
    imported_file,
};

[[nodiscard]] negaflow::imaging::InfraredDetectionResult
detect_infrared_defects_from_files(
    const std::filesystem::path& visible_path,
    const std::filesystem::path& infrared_path,
    InfraredVisibleSourceKind visible_source_kind,
    const negaflow::imaging::InfraredDetectorParameters& parameters,
    negaflow::core::CancelFlag cancel,
    negaflow::color::InputGammaInterpretation input_gamma = {}) noexcept;

}  // namespace negaflow::abi::detail
