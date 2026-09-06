#pragma once
#include "decoded_source_store.h"
#include "negaflow/imaging/scanner_tiff_to_working.h"

namespace negaflow::pipeline::develop_export_detail {
[[nodiscard]] negaflow::imaging::StreamedScannerToWorkingResult decode_input_gamma_preview(
    const DevelopExportRequest& request, const ObservedSource& observed,
    const negaflow::imageio::WicTiffDecodeControl& control,
    std::uint32_t box_width, std::uint32_t box_height) noexcept;
}
