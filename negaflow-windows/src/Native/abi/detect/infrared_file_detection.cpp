#include "detect/infrared_file_detection.h"

#include "negaflow/imaging/infrared_plane_resample.h"
#include "negaflow/imaging/scanner_tiff_to_working.h"
#include "negaflow/imaging/scanner_to_working.h"
#include "negaflow/core/parallel_rows.h"
#include "negaflow/imageio/wic_standard_image_decoder.h"
#include "negaflow/imageio/wic_tiff_decoder.h"
#include "negaflow/pipeline/gpu_accelerator.h"
#include "negaflow/pipeline/stage_timing.h"

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdint>
#include <cwctype>
#include <future>
#include <limits>
#include <new>
#include <span>
#include <utility>
#include <vector>

namespace negaflow::abi::detail {
namespace {

[[nodiscard]] bool is_tiff_path(const std::filesystem::path& path) {
    std::wstring extension = path.extension().wstring();
    std::transform(
        extension.begin(), extension.end(), extension.begin(),
        [](const wchar_t value) {
            return static_cast<wchar_t>(std::towlower(value));
        });
    return extension == L".tif" || extension == L".tiff";
}

class InfraredPlaneSink final : public negaflow::imageio::WicTiffRowSink {
public:
    InfraredPlaneSink(
        const bool allow_gray,
        const negaflow::core::CancelFlag cancel) noexcept
        : allow_gray_(allow_gray), cancel_(cancel) {}

    bool begin(const negaflow::imageio::WicTiffFrameView& frame) noexcept override {
        try {
            const bool valid_layout =
                frame.layout == negaflow::imageio::DecodedPixelLayout::rgb16 ||
                frame.layout == negaflow::imageio::DecodedPixelLayout::rgba16 ||
                (allow_gray_ &&
                 frame.layout == negaflow::imageio::DecodedPixelLayout::gray16);
            channels_ = negaflow::imageio::channel_count(frame.layout);
            const std::uint64_t area = static_cast<std::uint64_t>(frame.width) * frame.height;
            if (!valid_layout || channels_ == 0U || frame.width == 0U || frame.height == 0U ||
                area > std::numeric_limits<std::size_t>::max() || cancel_.requested()) {
                return false;
            }
            width_ = frame.width;
            height_ = frame.height;
            values_.assign(static_cast<std::size_t>(area), 0.0F);
            return true;
        } catch (...) {
            return false;
        }
    }

    bool write(const negaflow::imageio::WicTiffRowChunk& rows) noexcept override {
        if (cancel_.requested() || rows.first_row != next_row_ || rows.row_count == 0U ||
            rows.first_row > height_ || rows.row_count > height_ - rows.first_row ||
            rows.stride_bytes % sizeof(std::uint16_t) != 0U) {
            return false;
        }
        const std::size_t row_samples = rows.stride_bytes / sizeof(std::uint16_t);
        if (row_samples != static_cast<std::size_t>(width_) * channels_ ||
            rows.samples.size() != row_samples * rows.row_count) {
            return false;
        }
        for (std::uint32_t row = 0U; row < rows.row_count; ++row) {
            const auto* source = rows.samples.data() + static_cast<std::size_t>(row) * row_samples;
            auto* destination = values_.data() +
                static_cast<std::size_t>(rows.first_row + row) * width_;
            for (std::uint32_t x = 0U; x < width_; ++x) {
                destination[x] = static_cast<float>(source[static_cast<std::size_t>(x) * channels_]) /
                    65'535.0F;
            }
        }
        next_row_ += rows.row_count;
        return true;
    }

    void complete(const negaflow::imageio::WicTiffDecodeStatus status) noexcept override {
        complete_ = status == negaflow::imageio::WicTiffDecodeStatus::ok && next_row_ == height_;
        if (!complete_) std::vector<float>{}.swap(values_);
    }

    [[nodiscard]] bool complete() const noexcept { return complete_; }
    [[nodiscard]] std::uint32_t width() const noexcept { return width_; }
    [[nodiscard]] std::uint32_t height() const noexcept { return height_; }
    [[nodiscard]] std::vector<float>& values() noexcept { return values_; }

private:
    bool allow_gray_{false};
    negaflow::core::CancelFlag cancel_{};
    std::uint8_t channels_{0U};
    std::uint32_t width_{0U};
    std::uint32_t height_{0U};
    std::uint32_t next_row_{0U};
    bool complete_{false};
    std::vector<float> values_{};
};

enum class WorkingRedDecodeStatus {
    failure,
    requires_full_working_conversion,
    ok,
};

class WorkingRedPlaneSink final : public negaflow::imageio::WicTiffRowSink {
public:
    explicit WorkingRedPlaneSink(const negaflow::core::CancelFlag cancel) noexcept
        : cancel_(cancel) {}

    bool begin(const negaflow::imageio::WicTiffFrameView& frame) noexcept override {
        try {
            if (!frame.icc_profile.empty()) {
                status_ = WorkingRedDecodeStatus::requires_full_working_conversion;
                return false;
            }
            const bool rgb = frame.layout == negaflow::imageio::DecodedPixelLayout::rgb16;
            const bool rgba = frame.layout == negaflow::imageio::DecodedPixelLayout::rgba16;
            if ((!rgb && !rgba) ||
                (rgb && frame.alpha_mode != negaflow::imageio::AlphaMode::opaque) ||
                (rgba && frame.alpha_mode != negaflow::imageio::AlphaMode::associated &&
                 frame.alpha_mode != negaflow::imageio::AlphaMode::unassociated) ||
                frame.width == 0U || frame.height == 0U || cancel_.requested()) {
                return false;
            }
            const std::uint8_t channels = negaflow::imageio::channel_count(frame.layout);
            const std::uint64_t area = static_cast<std::uint64_t>(frame.width) * frame.height;
            if (channels == 0U ||
                frame.stride_bytes != static_cast<std::uint64_t>(frame.width) * channels *
                    sizeof(std::uint16_t) ||
                area > std::numeric_limits<std::size_t>::max()) {
                return false;
            }
            width_ = frame.width;
            height_ = frame.height;
            channels_ = channels;
            associated_ = frame.alpha_mode == negaflow::imageio::AlphaMode::associated;
            values_.assign(static_cast<std::size_t>(area), 0.0F);
            status_ = WorkingRedDecodeStatus::ok;
            active_ = true;
            return true;
        } catch (...) {
            return false;
        }
    }

    bool write(const negaflow::imageio::WicTiffRowChunk& rows) noexcept override {
        if (!active_ || cancel_.requested() || rows.first_row != next_row_ ||
            rows.row_count == 0U || rows.first_row > height_ ||
            rows.row_count > height_ - rows.first_row ||
            rows.stride_bytes % sizeof(std::uint16_t) != 0U) {
            return false;
        }
        const std::size_t row_samples = rows.stride_bytes / sizeof(std::uint16_t);
        if (row_samples != static_cast<std::size_t>(width_) * channels_ ||
            rows.samples.size() != row_samples * rows.row_count) {
            return false;
        }
        constexpr float scale = 1.0F / 65'535.0F;
        negaflow::core::for_each_row_block(
            rows.row_count,
            static_cast<std::uint64_t>(rows.stride_bytes + width_ * sizeof(float)) *
                rows.row_count,
            [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
                for (std::uint32_t row = first_row; row < first_row + row_count; ++row) {
                    const auto* source = rows.samples.data() +
                        static_cast<std::size_t>(row) * row_samples;
                    auto* destination = values_.data() +
                        static_cast<std::size_t>(rows.first_row + row) * width_;
                    for (std::uint32_t x = 0U; x < width_; ++x) {
                        const std::size_t offset = static_cast<std::size_t>(x) * channels_;
                        const std::uint16_t red = associated_
                            ? unassociate(source[offset], source[offset + 3U])
                            : source[offset];
                        destination[x] = static_cast<float>(red) * scale;
                    }
                }
            });
        next_row_ += rows.row_count;
        return !cancel_.requested();
    }

    void complete(const negaflow::imageio::WicTiffDecodeStatus status) noexcept override {
        active_ = false;
        if (status_ == WorkingRedDecodeStatus::requires_full_working_conversion) return;
        if (status != negaflow::imageio::WicTiffDecodeStatus::ok ||
            next_row_ != height_) {
            status_ = WorkingRedDecodeStatus::failure;
            std::vector<float>{}.swap(values_);
        }
    }

    [[nodiscard]] WorkingRedDecodeStatus status() const noexcept { return status_; }
    [[nodiscard]] std::uint32_t width() const noexcept { return width_; }
    [[nodiscard]] std::uint32_t height() const noexcept { return height_; }
    [[nodiscard]] std::vector<float>& values() noexcept { return values_; }

private:
    [[nodiscard]] static std::uint16_t unassociate(
        const std::uint16_t component,
        const std::uint16_t alpha) noexcept {
        if (alpha == 0U) return 0U;
        const std::uint64_t restored =
            (static_cast<std::uint64_t>(component) * 65'535U + alpha / 2U) / alpha;
        return static_cast<std::uint16_t>(std::min<std::uint64_t>(restored, 65'535U));
    }

    negaflow::core::CancelFlag cancel_{};
    WorkingRedDecodeStatus status_{WorkingRedDecodeStatus::failure};
    std::uint8_t channels_{0U};
    std::uint32_t width_{0U};
    std::uint32_t height_{0U};
    std::uint32_t next_row_{0U};
    bool associated_{false};
    bool active_{false};
    std::vector<float> values_{};
};

struct DecodedWorkingRedPlane final {
    WorkingRedDecodeStatus status{WorkingRedDecodeStatus::failure};
    std::uint32_t width{0U};
    std::uint32_t height{0U};
    std::vector<float> values{};
};

struct DecodedInfraredPlane final {
    bool complete{false};
    std::uint32_t width{0U};
    std::uint32_t height{0U};
    std::uint64_t decode_microseconds{0U};
    std::vector<float> values{};
};

using TimingClock = std::chrono::steady_clock;

[[nodiscard]] std::uint64_t elapsed_microseconds(
    const TimingClock::time_point started,
    const TimingClock::time_point finished) noexcept {
    return static_cast<std::uint64_t>(
        std::chrono::duration_cast<std::chrono::microseconds>(finished - started).count());
}

[[nodiscard]] DecodedInfraredPlane decode_infrared_plane(
    const std::filesystem::path& path,
    const negaflow::imageio::WicTiffDecodeControl& control,
    const negaflow::core::CancelFlag cancel,
    const bool trace) noexcept {
    const auto started = trace ? TimingClock::now() : TimingClock::time_point{};
    InfraredPlaneSink sink{true, cancel};
    const auto decoded = negaflow::imageio::decode_tiff_rows_with_wic(
        path, sink, {}, control);
    if (decoded.status != negaflow::imageio::WicTiffDecodeStatus::ok ||
        !sink.complete()) {
        return {};
    }
    return DecodedInfraredPlane{
        true,
        sink.width(),
        sink.height(),
        trace ? elapsed_microseconds(started, TimingClock::now()) : 0U,
        std::move(sink.values())};
}

[[nodiscard]] DecodedWorkingRedPlane decode_working_red_plane(
    const std::filesystem::path& path,
    const negaflow::imageio::WicTiffDecodeControl& control,
    const negaflow::core::CancelFlag cancel) noexcept {
    WorkingRedPlaneSink sink{cancel};
    const auto decoded = negaflow::imageio::decode_tiff_rows_with_wic(
        path, sink, {}, control);
    if (sink.status() == WorkingRedDecodeStatus::requires_full_working_conversion) {
        return {WorkingRedDecodeStatus::requires_full_working_conversion};
    }
    if (decoded.status != negaflow::imageio::WicTiffDecodeStatus::ok ||
        sink.status() != WorkingRedDecodeStatus::ok) {
        return {};
    }
    return DecodedWorkingRedPlane{
        WorkingRedDecodeStatus::ok,
        sink.width(),
        sink.height(),
        std::move(sink.values())};
}

[[nodiscard]] negaflow::imaging::InfraredDetectionResult failure(
    const negaflow::imaging::InfraredDetectionStatus status) noexcept {
    negaflow::imaging::InfraredDetectionResult result{};
    result.status = status;
    return result;
}

[[nodiscard]] bool extract_working_red(
    const negaflow::imaging::WorkingImage& working,
    std::vector<float>& values,
    std::uint32_t& width,
    std::uint32_t& height) {
    width = working.width;
    height = working.height;
    const std::size_t required = static_cast<std::size_t>(working.stride_pixels) * height;
    if (working.stride_pixels < width || working.pixels.size() < required) return false;
    values.resize(static_cast<std::size_t>(width) * height);
    negaflow::core::for_each_row_block(
        height,
        static_cast<std::uint64_t>(width) * height,
        [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
            for (std::uint32_t y = first_row; y < first_row + row_count; ++y) {
                const auto* source = working.pixels.data() +
                    static_cast<std::size_t>(y) * working.stride_pixels;
                auto* destination = values.data() + static_cast<std::size_t>(y) * width;
                for (std::uint32_t x = 0U; x < width; ++x) {
                    destination[x] = source[x].red;
                }
            }
        });
    return true;
}

}  // namespace

negaflow::imaging::InfraredDetectionResult detect_infrared_defects_from_files(
    const std::filesystem::path& visible_path,
    const std::filesystem::path& infrared_path,
    InfraredVisibleSourceKind visible_source_kind,
    const negaflow::imaging::InfraredDetectorParameters& parameters,
    const negaflow::core::CancelFlag cancel) noexcept {
    if (visible_path.empty() || infrared_path.empty()) {
        return failure(negaflow::imaging::InfraredDetectionStatus::unreadable);
    }
    if (cancel.requested()) {
        return failure(negaflow::imaging::InfraredDetectionStatus::cancelled);
    }
    try {
        const bool trace = negaflow::pipeline::stage_timing_enabled();
        const auto started = trace ? TimingClock::now() : TimingClock::time_point{};
        const bool visible_is_tiff = is_tiff_path(visible_path);
        if (visible_source_kind == InfraredVisibleSourceKind::infer_from_extension) {
            visible_source_kind = visible_is_tiff
                ? InfraredVisibleSourceKind::scanner_tiff
                : InfraredVisibleSourceKind::imported_file;
        }

        negaflow::imageio::WicTiffDecodeControl visible_control{};
        visible_control.rows_per_copy = 32U;
        visible_control.select_first_frame = true;
        visible_control.orientation_policy =
            visible_source_kind == InfraredVisibleSourceKind::imported_file
                ? negaflow::imageio::WicTiffOrientationPolicy::apply_metadata
                : negaflow::imageio::WicTiffOrientationPolicy::ignore_metadata;
        auto infrared_control = visible_control;
        infrared_control.orientation_policy =
            negaflow::imageio::WicTiffOrientationPolicy::ignore_metadata;
        auto infrared_future = std::async(
            std::launch::async,
            [infrared_path, infrared_control, cancel, trace]() noexcept {
                return decode_infrared_plane(
                    infrared_path,
                    infrared_control,
                    cancel,
                    trace);
            });
        std::vector<float> visible_values{};
        std::uint32_t visible_width = 0U;
        std::uint32_t visible_height = 0U;
        if (visible_is_tiff) {
            auto direct = decode_working_red_plane(visible_path, visible_control, cancel);
            if (direct.status == WorkingRedDecodeStatus::ok) {
                visible_values = std::move(direct.values);
                visible_width = direct.width;
                visible_height = direct.height;
            } else if (direct.status ==
                       WorkingRedDecodeStatus::requires_full_working_conversion) {
                // 위 fast path 시도가 `begin` 에서 빠지기 전에 이미 같은 파일의 압축 stream 을
                // ADR-0011 대로 전수 검증했습니다. 여기서 또 하면 compression=5 파일에서 LZW
                // 전수 walk 를 두 번 합니다 — 실제 `GT-X900_frame_17`(LZW·492스트립·RGBA·ICC)
                // 에서 회당 약 371ms 입니다. 검증은 그대로 한 번 하고, 중복만 없앱니다.
                auto full_control = visible_control;
                full_control.validate_compressed_streams = false;
                const auto visible = negaflow::imaging::decode_scanner_tiff_to_working_rows(
                    visible_path, {}, {}, full_control);
                if (visible.decode.status != negaflow::imageio::WicTiffDecodeStatus::ok ||
                    visible.working.status != negaflow::imaging::ScannerToWorkingStatus::ok ||
                    !extract_working_red(
                        visible.working.image,
                        visible_values,
                        visible_width,
                        visible_height)) {
                    return failure(negaflow::imaging::InfraredDetectionStatus::unreadable);
                }
            } else {
                return failure(negaflow::imaging::InfraredDetectionStatus::unreadable);
            }
            if (cancel.requested()) {
                return failure(negaflow::imaging::InfraredDetectionStatus::cancelled);
            }
        } else {
            const auto decoded = negaflow::imageio::decode_standard_image_with_wic(visible_path);
            if (cancel.requested()) {
                return failure(negaflow::imaging::InfraredDetectionStatus::cancelled);
            }
            if (decoded.status != negaflow::imageio::WicStandardImageDecodeStatus::ok) {
                return failure(negaflow::imaging::InfraredDetectionStatus::unreadable);
            }
            auto working = negaflow::imaging::convert_scanner_to_working(decoded.image);
            if (working.status != negaflow::imaging::ScannerToWorkingStatus::ok) {
                return failure(negaflow::imaging::InfraredDetectionStatus::unreadable);
            }
            if (!extract_working_red(
                    working.image,
                    visible_values,
                    visible_width,
                    visible_height)) {
                return failure(negaflow::imaging::InfraredDetectionStatus::unreadable);
            }
        }

        const auto visible_finished = trace ? TimingClock::now() : TimingClock::time_point{};
        const auto join_started = visible_finished;
        DecodedInfraredPlane infrared = infrared_future.get();
        const auto join_finished = trace ? TimingClock::now() : TimingClock::time_point{};
        if (cancel.requested()) {
            return failure(negaflow::imaging::InfraredDetectionStatus::cancelled);
        }
        if (!infrared.complete) {
            return failure(negaflow::imaging::InfraredDetectionStatus::unreadable);
        }
        std::uint64_t resample_microseconds = 0U;
        if (infrared.width != visible_width || infrared.height != visible_height) {
            const auto resample_started = trace ? TimingClock::now() : TimingClock::time_point{};
            std::vector<float> resampled{};
            if (!negaflow::imaging::resample_infrared_plane_to_extent(
                    infrared.values,
                    infrared.width,
                    infrared.height,
                    visible_width,
                    visible_height,
                    resampled)) {
                return failure(negaflow::imaging::InfraredDetectionStatus::unreadable);
            }
            infrared.values = std::move(resampled);
            if (trace) {
                resample_microseconds = elapsed_microseconds(
                    resample_started,
                    TimingClock::now());
            }
        }

        // IR은 풀해상도이고 프레임마다 치수가 달라질 수 있습니다. interactive preview용 이전
        // 두 번째 texture 치수를 함께 붙들면 실제 22쌍에서 private bytes가 16GB까지 남았습니다.
        // 사진 FIFO 캐시와 무관한 일회 작업 자원이므로 검출 전후에만 반환합니다.
        negaflow::pipeline::GpuAccelerator::shared().release_transient_resources();
        const auto core_started = trace ? TimingClock::now() : TimingClock::time_point{};
        auto result = negaflow::imaging::detect_infrared_defects(
            infrared.values,
            visible_values,
            visible_width,
            visible_height,
            parameters,
            cancel);
        negaflow::pipeline::GpuAccelerator::shared().release_transient_resources();
        if (trace) {
            const auto finished = TimingClock::now();
            (void)std::fprintf(
                stderr,
                "[infrared file timing] visible=%llu ir=%llu join=%llu resample=%llu "
                "core=%llu total=%llu us\n",
                static_cast<unsigned long long>(elapsed_microseconds(started, visible_finished)),
                static_cast<unsigned long long>(infrared.decode_microseconds),
                static_cast<unsigned long long>(elapsed_microseconds(join_started, join_finished)),
                static_cast<unsigned long long>(resample_microseconds),
                static_cast<unsigned long long>(elapsed_microseconds(core_started, finished)),
                static_cast<unsigned long long>(elapsed_microseconds(started, finished)));
        }
        return result;
    } catch (const std::bad_alloc&) {
        return failure(negaflow::imaging::InfraredDetectionStatus::allocation_failed);
    } catch (...) {
        return failure(negaflow::imaging::InfraredDetectionStatus::unreadable);
    }
}

}  // namespace negaflow::abi::detail
