#include "input_gamma_preview_decode.h"
#include <utility>

namespace negaflow::pipeline::develop_export_detail {
negaflow::imaging::StreamedScannerToWorkingResult decode_input_gamma_preview(
    const DevelopExportRequest& request, const ObservedSource& observed,
    const negaflow::imageio::WicTiffDecodeControl& control,
    const std::uint32_t box_width, const std::uint32_t box_height) noexcept {
    using namespace negaflow::imaging;
    using namespace negaflow::imageio;
    StreamedScannerToWorkingResult result{};
    try {
        auto source = encoded_source_try_take(request.source, observed.before.observation, box_width, box_height);
        if (!source) {
            if (!is_input_gamma_source_supported(request.source)) {
                result.decode.status = WicTiffDecodeStatus::row_sink_failed;
                result.working.status = ScannerToWorkingStatus::unsupported_input_gamma;
                return result;
            }
            auto decoded = decode_tiff_with_wic(request.source, {}, control);
            result.decode.status = decoded.status;
            if (decoded.status != WicTiffDecodeStatus::ok) { return result; }
            const auto after = observe_image_file(request.source);
            if (after.status != ImageFileObservationStatus::ok ||
                !same_image_file_observation(observed.before.observation, after.observation)) {
                result.decode.status = WicTiffDecodeStatus::row_sink_failed;
                return result;
            }
            source = std::make_shared<const DecodedImage>(std::move(decoded.image));
            encoded_source_put(request.source, observed.before.observation, box_width, box_height, source);
        }
        result.working = convert_cached_scanner_rows(*source, control, request.input_gamma);
        result.decode.status = result.working.status == ScannerToWorkingStatus::ok ? WicTiffDecodeStatus::ok
            : result.working.status == ScannerToWorkingStatus::cancelled ? WicTiffDecodeStatus::cancelled
            : WicTiffDecodeStatus::row_sink_failed;
    } catch (...) {
        result.decode.status = WicTiffDecodeStatus::row_sink_failed;
        result.working.status = ScannerToWorkingStatus::allocation_failed;
    }
    return result;
}
}
