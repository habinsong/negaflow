#include "decode.h"

#include "export/support/outcome.h"

#include "negaflow/imageio/wic_standard_image_decoder.h"
#include "negaflow/imaging/scanner_tiff_to_working.h"

#include <cwchar>
#include <utility>

namespace negaflow::pipeline::develop_export_detail {
namespace {

[[nodiscard]] bool is_tiff_source(const std::filesystem::path& path) noexcept {
    const std::wstring extension = path.extension().wstring();
    return _wcsicmp(extension.c_str(), L".tif") == 0 ||
           _wcsicmp(extension.c_str(), L".tiff") == 0;
}

// macOS `cachedInteractivePreviewRaw` / `preloadedPreviewRaw` 에 해당합니다.
// 같은 파일·같은 관측이면 디스크 TIFF 를 다시 읽지 않습니다. 프로세스 하나이므로
// 단일 슬롯이면 충분합니다 — 프레임이 바뀌면 경로/관측이 달라져 자동으로 교체됩니다.
struct DecodedSourceCache final {
    std::filesystem::path path{};
    negaflow::imageio::ImageFileObservation observation{};
    negaflow::imaging::WorkingImage image{};
    bool occupied{false};
};

DecodedSourceCache g_decoded_source_cache{};

[[nodiscard]] bool cache_matches(
    const std::filesystem::path& path,
    const negaflow::imageio::ImageFileObservation& observation) noexcept {
    return g_decoded_source_cache.occupied &&
           g_decoded_source_cache.path == path &&
           negaflow::imageio::same_image_file_observation(
               g_decoded_source_cache.observation,
               observation);
}

}  // namespace

std::optional<DevelopExportOutcome> decode_source(
    const DevelopExportRequest& request,
    RunTracker& tracker,
    std::stop_source& stop,
    const ObservedSource& observed,
    negaflow::imaging::WorkingImage& decoded_image) noexcept {
    tracker.begin(DevelopExportStage::decode, cost_of(decode_cost, true));
    if (cache_matches(request.source, observed.before.observation))
    {
        decoded_image = g_decoded_source_cache.image;
        tracker.finish();
        if (tracker.cancelled()) {
            return cancelled_outcome(DevelopExportStage::decode);
        }
        return std::nullopt;
    }

    DecodeProgressBridge decode_progress{tracker, stop};
    negaflow::imageio::WicTiffDecodeControl decode_control{};
    decode_control.rows_per_copy = request.rows_per_copy;
    decode_control.stop_token = stop.get_token();
    decode_control.progress_observer = &decode_progress;
    if (is_tiff_source(request.source)) {
        auto prepared = negaflow::imaging::decode_scanner_tiff_to_working_rows(
            request.source,
            {},
            {},
            decode_control);
        if (prepared.decode.status == negaflow::imageio::WicTiffDecodeStatus::cancelled) {
            return cancelled_outcome(DevelopExportStage::decode);
        }
        if (prepared.decode.status != negaflow::imageio::WicTiffDecodeStatus::ok) {
            if (prepared.decode.status ==
                    negaflow::imageio::WicTiffDecodeStatus::row_sink_failed &&
                prepared.working.status !=
                    negaflow::imaging::ScannerToWorkingStatus::invalid_argument) {
                return fail(
                    DevelopExportStage::decode,
                    negaflow::imaging::scanner_to_working_status_name(
                        prepared.working.status),
                    prepared.working.info.native_error_code);
            }
            return fail(
                DevelopExportStage::decode,
                negaflow::imageio::wic_tiff_decode_status_name(prepared.decode.status));
        }
        if (prepared.working.status != negaflow::imaging::ScannerToWorkingStatus::ok) {
            return fail(
                DevelopExportStage::decode,
                negaflow::imaging::scanner_to_working_status_name(
                    prepared.working.status),
                prepared.working.info.native_error_code);
        }
        decoded_image = std::move(prepared.working.image);
    } else {
        const negaflow::imageio::WicStandardImageDecodeResult decoded =
            negaflow::imageio::decode_standard_image_with_wic(
                request.source,
                {},
                stop.get_token());
        if (decoded.status == negaflow::imageio::WicStandardImageDecodeStatus::cancelled) {
            return cancelled_outcome(DevelopExportStage::decode);
        }
        if (decoded.status != negaflow::imageio::WicStandardImageDecodeStatus::ok) {
            return fail(
                DevelopExportStage::decode,
                negaflow::imageio::wic_standard_image_decode_status_name(decoded.status));
        }
        negaflow::imaging::ScannerToWorkingResult working =
            negaflow::imaging::convert_scanner_to_working(decoded.image);
        if (working.status != negaflow::imaging::ScannerToWorkingStatus::ok) {
            return fail(
                DevelopExportStage::decode,
                negaflow::imaging::scanner_to_working_status_name(working.status),
                working.info.native_error_code);
        }
        decoded_image = std::move(working.image);
    }

    const negaflow::imageio::ImageFileObservationResult after =
        negaflow::imageio::observe_image_file(request.source);
    if (after.status != negaflow::imageio::ImageFileObservationStatus::ok) {
        return fail(
            DevelopExportStage::observe_source_after,
            negaflow::imageio::image_file_observation_status_name(after.status),
            after.native_error_code);
    }
    if (!negaflow::imageio::same_image_file_observation(
            observed.before.observation,
            after.observation)) {
        return fail(
            DevelopExportStage::observe_source_after, "source_changed_during_decode");
    }

    g_decoded_source_cache.path = request.source;
    g_decoded_source_cache.observation = observed.before.observation;
    g_decoded_source_cache.image = decoded_image;
    g_decoded_source_cache.occupied = true;

    tracker.finish();
    if (tracker.cancelled()) {
        return cancelled_outcome(DevelopExportStage::decode);
    }
    return std::nullopt;
}

}  // namespace negaflow::pipeline::develop_export_detail
