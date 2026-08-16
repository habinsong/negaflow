#include "negaflow/imaging/scanner_tiff_to_working.h"

#include "icm_rgb16_transform.h"
#include "negaflow/color/srgb_transfer.h"
#include "scanner_to_working_detail.h"

#include <Windows.h>

#include <algorithm>
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

            std::uint64_t channels = 0U;
            switch (frame.layout) {
                case negaflow::imageio::DecodedPixelLayout::rgb16:
                    channels = 3U;
                    if (frame.alpha_mode != negaflow::imageio::AlphaMode::opaque) {
                        result_.status = ScannerToWorkingStatus::unsupported_alpha;
                        return false;
                    }
                    break;
                case negaflow::imageio::DecodedPixelLayout::rgba16:
                    channels = 4U;
                    if (frame.alpha_mode != negaflow::imageio::AlphaMode::associated &&
                        frame.alpha_mode != negaflow::imageio::AlphaMode::unassociated) {
                        result_.status = ScannerToWorkingStatus::unsupported_alpha;
                        return false;
                    }
                    break;
                default:
                    result_.status = ScannerToWorkingStatus::invalid_argument;
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

    [[nodiscard]] ScannerToWorkingStatus convert_linear_rows(
        const negaflow::imageio::WicTiffRowChunk& rows) noexcept {
        constexpr float u16_scale = 1.0F / 65'535.0F;
        const std::size_t channels = negaflow::imageio::channel_count(layout_);
        const std::size_t source_stride =
            source_stride_bytes_ / sizeof(std::uint16_t);
        for (std::uint32_t row = 0U; row < rows.row_count; ++row) {
            if (stop_token_.stop_requested()) {
                return ScannerToWorkingStatus::cancelled;
            }
            const std::uint16_t* const source =
                rows.samples.data() + static_cast<std::size_t>(row) * source_stride;
            negaflow::core::Rgba32F* const destination =
                result_.image.pixels.data() +
                static_cast<std::size_t>(rows.first_row + row) * width_;
            for (std::uint32_t column = 0U; column < width_; ++column) {
                const std::size_t offset = static_cast<std::size_t>(column) * channels;
                const bool associated =
                    alpha_mode_ == negaflow::imageio::AlphaMode::associated;
                const std::uint16_t alpha16 = layout_ == negaflow::imageio::DecodedPixelLayout::rgba16
                    ? source[offset + 3U]
                    : 65'535U;
                destination[column] = {
                    associated ? static_cast<float>(unassociate_component(source[offset], alpha16)) * u16_scale
                               : static_cast<float>(source[offset]) * u16_scale,
                    associated ? static_cast<float>(unassociate_component(source[offset + 1U], alpha16)) * u16_scale
                               : static_cast<float>(source[offset + 1U]) * u16_scale,
                    associated ? static_cast<float>(unassociate_component(source[offset + 2U], alpha16)) * u16_scale
                               : static_cast<float>(source[offset + 2U]) * u16_scale,
                    row_alpha(source, offset),
                };
            }
        }
        return ScannerToWorkingStatus::ok;
    }

    [[nodiscard]] ScannerToWorkingStatus convert_icc_rows(
        const negaflow::imageio::WicTiffRowChunk& rows) {
        const std::uint64_t rgb_stride_bytes =
            static_cast<std::uint64_t>(width_) * 3ULL * sizeof(std::uint16_t);
        const std::uint64_t rgb_chunk_bytes = rgb_stride_bytes * rows.row_count;
        const bool needs_rgb_copy =
            layout_ == negaflow::imageio::DecodedPixelLayout::rgba16;
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
            for (std::uint32_t row = 0U; row < rows.row_count; ++row) {
                const std::uint16_t* const source_row =
                    rows.samples.data() + static_cast<std::size_t>(row) * source_stride;
                std::uint16_t* const destination_row =
                    packed_rgb_.data() + static_cast<std::size_t>(row) * width_ * 3U;
                for (std::uint32_t column = 0U; column < width_; ++column) {
                    const std::size_t source_offset = static_cast<std::size_t>(column) * 4U;
                    const std::size_t destination_offset =
                        static_cast<std::size_t>(column) * 3U;
                    const bool associated =
                        alpha_mode_ == negaflow::imageio::AlphaMode::associated;
                    const std::uint16_t alpha = source_row[source_offset + 3U];
                    destination_row[destination_offset] = associated
                        ? unassociate_component(source_row[source_offset], alpha)
                        : source_row[source_offset];
                    destination_row[destination_offset + 1U] = associated
                        ? unassociate_component(source_row[source_offset + 1U], alpha)
                        : source_row[source_offset + 1U];
                    destination_row[destination_offset + 2U] = associated
                        ? unassociate_component(source_row[source_offset + 2U], alpha)
                        : source_row[source_offset + 2U];
                }
            }
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
        for (std::uint32_t row = 0U; row < rows.row_count; ++row) {
            if (stop_token_.stop_requested()) {
                return ScannerToWorkingStatus::cancelled;
            }
            const std::uint16_t* const source_row =
                encoded_srgb_.data() + static_cast<std::size_t>(row) * encoded_stride;
            negaflow::core::Rgba32F* const destination =
                result_.image.pixels.data() +
                static_cast<std::size_t>(rows.first_row + row) * width_;
            for (std::uint32_t column = 0U; column < width_; ++column) {
                const std::size_t offset = static_cast<std::size_t>(column) * 3U;
                const std::size_t input_offset = static_cast<std::size_t>(column) *
                    negaflow::imageio::channel_count(layout_);
                const std::uint16_t* const input_row = rows.samples.data() +
                    static_cast<std::size_t>(row) * (source_stride_bytes_ / sizeof(std::uint16_t));
                destination[column] = {
                    negaflow::color::srgb_encoded_to_linear(
                        static_cast<float>(source_row[offset]) * u16_scale),
                    negaflow::color::srgb_encoded_to_linear(
                        static_cast<float>(source_row[offset + 1U]) * u16_scale),
                    negaflow::color::srgb_encoded_to_linear(
                        static_cast<float>(source_row[offset + 2U]) * u16_scale),
                    row_alpha(input_row, input_offset),
                };
            }
        }
        return ScannerToWorkingStatus::ok;
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
