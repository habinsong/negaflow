#include "negaflow/imaging/scanner_tiff_to_working.h"

#include "icm_rgb16_transform.h"
#include "negaflow/color/srgb_transfer.h"
#include "negaflow/core/parallel_rows.h"
#include "scanner_to_working_detail.h"

#include <Windows.h>

#include <algorithm>
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <new>
#include <stop_token>
#include <utility>
#include <vector>

namespace negaflow::imaging {
namespace {

BOOL WINAPI icm_progress_callback(
    const ULONG /*maximum*/,
    const ULONG /*current*/,
    const LPARAM callback_data) noexcept {
    const auto* const stop_token =
        reinterpret_cast<const std::stop_token*>(callback_data);
    return stop_token != nullptr && stop_token->stop_requested() ? FALSE : TRUE;
}

class ScannerWorkingRowSink final : public negaflow::imageio::WicTiffRowSink {
public:
    ScannerWorkingRowSink(
        const ScannerToWorkingLimits& limits,
        const std::stop_token stop_token) noexcept
        : limits_(limits), stop_token_(stop_token) {}

    bool begin(const negaflow::imageio::WicTiffFrameView& frame) noexcept override {
        try {
            if (frame.width == 0U || frame.height == 0U) {
                result_.status = ScannerToWorkingStatus::invalid_dimensions;
                return false;
            }

            // `channel_count` 는 아는 layout 만 양수를 돌려줍니다. switch 에 default 를 두면
            // 새 layout 을 조용히 삼키므로, 알 수 없는 값은 여기서 한 번에 걸러냅니다.
            const std::uint64_t channels =
                negaflow::imageio::channel_count(frame.layout);
            if (channels == 0U) {
                result_.status = ScannerToWorkingStatus::invalid_argument;
                return false;
            }
            // alpha 계약은 rgba16 만 다릅니다. rgb16 과 스캐너 Gray 의 1채널 `gray16` 은
            // 불투명이어야 합니다. Gray 를 받는 이유는 macOS 가 `CIImage(cgImage:)` 로 회색
            // CGImage 를 그대로 받기 때문이며, 여기서 거부하면 Windows 만 Gray 스캔을
            // 통째로 못 읽습니다.
            const bool alpha_matches_layout =
                frame.layout == negaflow::imageio::DecodedPixelLayout::rgba16
                    ? (frame.alpha_mode == negaflow::imageio::AlphaMode::associated ||
                       frame.alpha_mode == negaflow::imageio::AlphaMode::unassociated)
                    : frame.alpha_mode == negaflow::imageio::AlphaMode::opaque;
            if (!alpha_matches_layout) {
                result_.status = ScannerToWorkingStatus::unsupported_alpha;
                return false;
            }

            const std::uint64_t expected_stride =
                static_cast<std::uint64_t>(frame.width) * channels *
                sizeof(std::uint16_t);
            if (expected_stride != frame.stride_bytes ||
                frame.stride_bytes % sizeof(std::uint16_t) != 0U) {
                result_.status = ScannerToWorkingStatus::invalid_stride;
                return false;
            }
            const std::uint64_t pixel_count =
                static_cast<std::uint64_t>(frame.width) * frame.height;
            if (pixel_count > std::numeric_limits<std::uint64_t>::max() /
                                  sizeof(negaflow::core::Rgba32F) ||
                pixel_count > std::numeric_limits<std::size_t>::max() /
                                  sizeof(negaflow::core::Rgba32F)) {
                result_.status = ScannerToWorkingStatus::size_overflow;
                return false;
            }
            const std::uint64_t working_bytes =
                pixel_count * sizeof(negaflow::core::Rgba32F);
            if (working_bytes > limits_.max_working_pixel_bytes) {
                result_.status = ScannerToWorkingStatus::memory_limit_exceeded;
                return false;
            }

            width_ = frame.width;
            height_ = frame.height;
            source_stride_bytes_ = frame.stride_bytes;
            layout_ = frame.layout;
            alpha_mode_ = frame.alpha_mode;
            result_.image.width = frame.width;
            result_.image.height = frame.height;
            result_.image.stride_pixels = frame.width;
            result_.image.pixels.resize(static_cast<std::size_t>(pixel_count));

            if (frame.icc_profile.empty()) {
                result_.info.transform = ScannerWorkingTransform::linear_scanner_raw;
            } else {
                result_.status = detail::validate_scanner_icc_profile(
                    frame.icc_profile,
                    limits_,
                    result_.icc_status,
                    result_.info);
                if (result_.status != ScannerToWorkingStatus::ok) {
                    return false;
                }
                result_.status =
                    transform_.initialize(frame.icc_profile, result_.info.native_error_code);
                if (result_.status != ScannerToWorkingStatus::ok) {
                    return false;
                }
                has_icc_ = true;
                result_.info.transform =
                    ScannerWorkingTransform::embedded_icc_windows_icm_srgb16;
                result_.info.intermediate_bits_per_color_channel = 16U;
            }

            result_.status = ScannerToWorkingStatus::ok;
            active_ = true;
            return true;
        } catch (const std::bad_alloc&) {
            result_.status = ScannerToWorkingStatus::allocation_failed;
            return false;
        } catch (...) {
            result_.status = ScannerToWorkingStatus::invalid_argument;
            return false;
        }
    }

    bool write(const negaflow::imageio::WicTiffRowChunk& rows) noexcept override {
        try {
            if (!active_ || stop_token_.stop_requested()) {
                result_.status = ScannerToWorkingStatus::cancelled;
                return false;
            }
            if (rows.first_row != next_row_ || rows.row_count == 0U ||
                rows.first_row > height_ || rows.row_count > height_ - rows.first_row ||
                rows.stride_bytes != source_stride_bytes_) {
                result_.status = ScannerToWorkingStatus::buffer_size_mismatch;
                return false;
            }
            const std::uint64_t expected_samples =
                static_cast<std::uint64_t>(source_stride_bytes_) * rows.row_count /
                sizeof(std::uint16_t);
            if (expected_samples != rows.samples.size()) {
                result_.status = ScannerToWorkingStatus::buffer_size_mismatch;
                return false;
            }

            const ScannerToWorkingStatus conversion_status =
                has_icc_ ? convert_icc_rows(rows) : convert_linear_rows(rows);
            if (conversion_status != ScannerToWorkingStatus::ok) {
                result_.status = conversion_status;
                return false;
            }
            next_row_ += rows.row_count;
            return true;
        } catch (const std::bad_alloc&) {
            result_.status = ScannerToWorkingStatus::allocation_failed;
            return false;
        } catch (...) {
            result_.status = ScannerToWorkingStatus::invalid_argument;
            return false;
        }
    }

    void complete(const negaflow::imageio::WicTiffDecodeStatus status) noexcept override {
        active_ = false;
        const bool succeeded =
            status == negaflow::imageio::WicTiffDecodeStatus::ok &&
            result_.status == ScannerToWorkingStatus::ok && next_row_ == height_;
        if (succeeded) {
            return;
        }
        if (status == negaflow::imageio::WicTiffDecodeStatus::cancelled) {
            result_.status = ScannerToWorkingStatus::cancelled;
        } else if (result_.status == ScannerToWorkingStatus::ok) {
            result_.status = ScannerToWorkingStatus::invalid_argument;
        }
        std::vector<negaflow::core::Rgba32F>{}.swap(result_.image.pixels);
        std::vector<std::uint16_t>{}.swap(packed_rgb_);
        std::vector<std::uint16_t>{}.swap(encoded_srgb_);
    }

    [[nodiscard]] ScannerToWorkingResult take_result() noexcept {
        return std::move(result_);
    }

    [[nodiscard]] std::uint64_t peak_temporary_pixel_bytes() const noexcept {
        return peak_temporary_pixel_bytes_;
    }

private:
    [[nodiscard]] std::uint16_t unassociate_component(
        const std::uint16_t component,
        const std::uint16_t alpha) const noexcept {
        if (alpha == 0U) {
            return 0U;
        }
        const std::uint64_t restored =
            (static_cast<std::uint64_t>(component) * 65'535U + alpha / 2U) / alpha;
        return static_cast<std::uint16_t>(std::min<std::uint64_t>(restored, 65'535U));
    }

    [[nodiscard]] float row_alpha(
        const std::uint16_t* const source,
        const std::size_t offset) const noexcept {
        constexpr float u16_scale = 1.0F / 65'535.0F;
        return layout_ == negaflow::imageio::DecodedPixelLayout::rgba16
            ? static_cast<float>(source[offset + 3U]) * u16_scale
            : 1.0F;
    }

    /// 행끼리 독립이므로 화소당 계산은 그대로 두고 행 블록으로만 나눕니다. 화소당 하던
    /// layout/alpha 판정은 루프 밖으로 뺐습니다. 결과 화소는 직렬판과 같습니다.
    [[nodiscard]] ScannerToWorkingStatus convert_linear_rows(
        const negaflow::imageio::WicTiffRowChunk& rows) noexcept {
        constexpr float u16_scale = 1.0F / 65'535.0F;
        const std::size_t channels = negaflow::imageio::channel_count(layout_);
        const std::size_t source_stride =
            source_stride_bytes_ / sizeof(std::uint16_t);
        const bool has_alpha =
            layout_ == negaflow::imageio::DecodedPixelLayout::rgba16;
        const bool associated =
            alpha_mode_ == negaflow::imageio::AlphaMode::associated;
        const negaflow::imageio::RgbSampleOffsets rgb =
            negaflow::imageio::rgb_sample_offsets(layout_);
        std::atomic<bool> cancelled{false};
        negaflow::core::for_each_row_block(
            rows.row_count,
            row_block_work_units(rows.row_count, channels),
            [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
                if (stop_token_.stop_requested()) {
                    cancelled.store(true, std::memory_order_relaxed);
                    return;
                }
                for (std::uint32_t row = first_row; row < first_row + row_count; ++row) {
                    const std::uint16_t* const source =
                        rows.samples.data() + static_cast<std::size_t>(row) * source_stride;
                    negaflow::core::Rgba32F* const destination =
                        result_.image.pixels.data() +
                        static_cast<std::size_t>(rows.first_row + row) * width_;
                    for (std::uint32_t column = 0U; column < width_; ++column) {
                        const std::size_t offset = static_cast<std::size_t>(column) * channels;
                        const std::uint16_t alpha16 = has_alpha ? source[offset + 3U] : 65'535U;
                        destination[column] = {
                            associated ? static_cast<float>(unassociate_component(source[offset + rgb.red], alpha16)) * u16_scale
                                       : static_cast<float>(source[offset + rgb.red]) * u16_scale,
                            associated ? static_cast<float>(unassociate_component(source[offset + rgb.green], alpha16)) * u16_scale
                                       : static_cast<float>(source[offset + rgb.green]) * u16_scale,
                            associated ? static_cast<float>(unassociate_component(source[offset + rgb.blue], alpha16)) * u16_scale
                                       : static_cast<float>(source[offset + rgb.blue]) * u16_scale,
                            has_alpha ? static_cast<float>(source[offset + 3U]) * u16_scale : 1.0F,
                        };
                    }
                }
            });
        return cancelled.load(std::memory_order_relaxed)
            ? ScannerToWorkingStatus::cancelled
            : ScannerToWorkingStatus::ok;
    }

    /// `parallel_rows.h` 가 경고하는 대로 출력 행 수가 아니라 실제로 읽고 쓰는 바이트를
    /// 넘깁니다. 화소당 원본 `channels` 개의 16-bit 표본을 읽고 16바이트를 씁니다.
    [[nodiscard]] std::uint64_t row_block_work_units(
        const std::uint32_t row_count,
        const std::size_t channels) const noexcept {
        return static_cast<std::uint64_t>(width_) * row_count *
            (channels * sizeof(std::uint16_t) + sizeof(negaflow::core::Rgba32F));
    }

    [[nodiscard]] ScannerToWorkingStatus convert_icc_rows(
        const negaflow::imageio::WicTiffRowChunk& rows) {
        const std::uint64_t rgb_stride_bytes =
            static_cast<std::uint64_t>(width_) * 3ULL * sizeof(std::uint16_t);
        const std::uint64_t rgb_chunk_bytes = rgb_stride_bytes * rows.row_count;
        // ICM 변환은 RGB16 만 받습니다. rgba 는 alpha 를 떼고, gray 는 한 표본을 세 채널로
        // 펴서 같은 입력 모양으로 맞춥니다.
        const bool needs_rgb_copy =
            layout_ != negaflow::imageio::DecodedPixelLayout::rgb16;
        if (needs_rgb_copy &&
            rgb_chunk_bytes > std::numeric_limits<std::uint64_t>::max() / 2U) {
            return ScannerToWorkingStatus::size_overflow;
        }
        const std::uint64_t temporary_bytes =
            rgb_chunk_bytes + (needs_rgb_copy ? rgb_chunk_bytes : 0ULL);
        if (rgb_stride_bytes > std::numeric_limits<std::uint32_t>::max() ||
            temporary_bytes > limits_.max_temporary_pixel_bytes ||
            rgb_chunk_bytes / sizeof(std::uint16_t) >
                std::numeric_limits<std::size_t>::max()) {
            return ScannerToWorkingStatus::memory_limit_exceeded;
        }
        peak_temporary_pixel_bytes_ =
            std::max(peak_temporary_pixel_bytes_, temporary_bytes);

        const std::uint16_t* source = rows.samples.data();
        std::uint32_t source_stride_bytes = source_stride_bytes_;
        if (needs_rgb_copy) {
            packed_rgb_.resize(
                static_cast<std::size_t>(rgb_chunk_bytes / sizeof(std::uint16_t)));
            const std::size_t source_stride =
                source_stride_bytes_ / sizeof(std::uint16_t);
            const bool associated =
                alpha_mode_ == negaflow::imageio::AlphaMode::associated;
            const std::size_t source_channels =
                negaflow::imageio::channel_count(layout_);
            const bool source_has_alpha =
                layout_ == negaflow::imageio::DecodedPixelLayout::rgba16;
            const negaflow::imageio::RgbSampleOffsets rgb =
                negaflow::imageio::rgb_sample_offsets(layout_);
            negaflow::core::for_each_row_block(
                rows.row_count,
                row_block_work_units(rows.row_count, source_channels),
                [&](const std::uint32_t first_row, const std::uint32_t block_rows) noexcept {
                    for (std::uint32_t row = first_row; row < first_row + block_rows; ++row) {
                        const std::uint16_t* const source_row =
                            rows.samples.data() + static_cast<std::size_t>(row) * source_stride;
                        std::uint16_t* const destination_row =
                            packed_rgb_.data() + static_cast<std::size_t>(row) * width_ * 3U;
                        for (std::uint32_t column = 0U; column < width_; ++column) {
                            const std::size_t source_offset =
                                static_cast<std::size_t>(column) * source_channels;
                            const std::size_t destination_offset =
                                static_cast<std::size_t>(column) * 3U;
                            const std::uint16_t alpha = source_has_alpha
                                ? source_row[source_offset + 3U]
                                : std::uint16_t{65'535U};
                            destination_row[destination_offset] = associated
                                ? unassociate_component(source_row[source_offset + rgb.red], alpha)
                                : source_row[source_offset + rgb.red];
                            destination_row[destination_offset + 1U] = associated
                                ? unassociate_component(source_row[source_offset + rgb.green], alpha)
                                : source_row[source_offset + rgb.green];
                            destination_row[destination_offset + 2U] = associated
                                ? unassociate_component(source_row[source_offset + rgb.blue], alpha)
                                : source_row[source_offset + rgb.blue];
                        }
                    }
                });
            source = packed_rgb_.data();
            source_stride_bytes = static_cast<std::uint32_t>(rgb_stride_bytes);
        }

        encoded_srgb_.resize(
            static_cast<std::size_t>(rgb_chunk_bytes / sizeof(std::uint16_t)));
        ScannerToWorkingStatus status = transform_.translate(
            source,
            width_,
            rows.row_count,
            source_stride_bytes,
            encoded_srgb_.data(),
            static_cast<std::uint32_t>(rgb_stride_bytes),
            result_.info.native_error_code,
            icm_progress_callback,
            reinterpret_cast<LPARAM>(&stop_token_));
        if (status != ScannerToWorkingStatus::ok) {
            return stop_token_.stop_requested() ? ScannerToWorkingStatus::cancelled : status;
        }

        constexpr float u16_scale = 1.0F / 65'535.0F;
        const std::size_t encoded_stride = static_cast<std::size_t>(width_) * 3U;
        const std::size_t channels = negaflow::imageio::channel_count(layout_);
        const std::size_t input_stride = source_stride_bytes_ / sizeof(std::uint16_t);
        const bool has_alpha =
            layout_ == negaflow::imageio::DecodedPixelLayout::rgba16;
        std::atomic<bool> cancelled{false};
        negaflow::core::for_each_row_block(
            rows.row_count,
            row_block_work_units(rows.row_count, channels),
            [&](const std::uint32_t first_row, const std::uint32_t block_rows) noexcept {
                if (stop_token_.stop_requested()) {
                    cancelled.store(true, std::memory_order_relaxed);
                    return;
                }
                for (std::uint32_t row = first_row; row < first_row + block_rows; ++row) {
                    const std::uint16_t* const source_row =
                        encoded_srgb_.data() + static_cast<std::size_t>(row) * encoded_stride;
                    const std::uint16_t* const input_row =
                        rows.samples.data() + static_cast<std::size_t>(row) * input_stride;
                    negaflow::core::Rgba32F* const destination =
                        result_.image.pixels.data() +
                        static_cast<std::size_t>(rows.first_row + row) * width_;
                    for (std::uint32_t column = 0U; column < width_; ++column) {
                        const std::size_t offset = static_cast<std::size_t>(column) * 3U;
                        const std::size_t input_offset =
                            static_cast<std::size_t>(column) * channels;
                        destination[column] = {
                            negaflow::color::srgb_encoded_to_linear(
                                static_cast<float>(source_row[offset]) * u16_scale),
                            negaflow::color::srgb_encoded_to_linear(
                                static_cast<float>(source_row[offset + 1U]) * u16_scale),
                            negaflow::color::srgb_encoded_to_linear(
                                static_cast<float>(source_row[offset + 2U]) * u16_scale),
                            has_alpha
                                ? static_cast<float>(input_row[input_offset + 3U]) * u16_scale
                                : 1.0F,
                        };
                    }
                }
            });
        return cancelled.load(std::memory_order_relaxed)
            ? ScannerToWorkingStatus::cancelled
            : ScannerToWorkingStatus::ok;
    }

    ScannerToWorkingLimits limits_{};
    std::stop_token stop_token_{};
    ScannerToWorkingResult result_{};
    detail::IcmRgb16Transform transform_{};
    std::vector<std::uint16_t> packed_rgb_{};
    std::vector<std::uint16_t> encoded_srgb_{};
    std::uint64_t peak_temporary_pixel_bytes_{0};
    std::uint32_t width_{0};
    std::uint32_t height_{0};
    std::uint32_t source_stride_bytes_{0};
    std::uint32_t next_row_{0};
    negaflow::imageio::DecodedPixelLayout layout_{
        negaflow::imageio::DecodedPixelLayout::rgb16};
    negaflow::imageio::AlphaMode alpha_mode_{negaflow::imageio::AlphaMode::opaque};
    bool has_icc_{false};
    bool active_{false};
};

}  // namespace

StreamedScannerToWorkingResult decode_scanner_tiff_to_working_rows(
    const std::filesystem::path& path,
    const negaflow::imageio::WicTiffDecodeLimits& decode_limits,
    const ScannerToWorkingLimits& working_limits,
    const negaflow::imageio::WicTiffDecodeControl& control) noexcept {
    StreamedScannerToWorkingResult result{};
    ScannerWorkingRowSink sink{working_limits, control.stop_token};
    result.decode = negaflow::imageio::decode_tiff_rows_with_wic(
        path,
        sink,
        decode_limits,
        control);
    result.working = sink.take_result();
    result.info.peak_conversion_temporary_pixel_bytes =
        sink.peak_temporary_pixel_bytes();
    if (result.decode.status == negaflow::imageio::WicTiffDecodeStatus::cancelled &&
        result.working.status == ScannerToWorkingStatus::invalid_argument) {
        result.working.status = ScannerToWorkingStatus::cancelled;
    }
    return result;
}

}  // namespace negaflow::imaging
