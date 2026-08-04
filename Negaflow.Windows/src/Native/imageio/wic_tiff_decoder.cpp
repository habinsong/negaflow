#include "negaflow/imageio/wic_tiff_decoder.h"

#include <Windows.h>
#include <Shlwapi.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <vector>

namespace negaflow::imageio {
namespace {

using Microsoft::WRL::ComPtr;

class ComApartment final {
public:
    ComApartment() noexcept : status_(CoInitializeEx(nullptr, COINIT_MULTITHREADED)) {}
    ComApartment(const ComApartment&) = delete;
    ComApartment& operator=(const ComApartment&) = delete;

    ~ComApartment() noexcept {
        if (status_ == S_OK || status_ == S_FALSE) {
            CoUninitialize();
        }
    }

    [[nodiscard]] HRESULT status() const noexcept {
        return status_;
    }

private:
    HRESULT status_;
};

class IStreamTiffReader final : public negaflow::core::TiffRandomAccessReader {
public:
    explicit IStreamTiffReader(IStream* const stream) noexcept : stream_(stream) {
        STATSTG statistics{};
        if (stream_ != nullptr && SUCCEEDED(stream_->Stat(&statistics, STATFLAG_NONAME)) &&
            statistics.type == STGTY_STREAM) {
            size_ = statistics.cbSize.QuadPart;
            valid_ = true;
        }
    }

    [[nodiscard]] bool valid() const noexcept {
        return valid_;
    }

    [[nodiscard]] std::uint64_t size() const noexcept override {
        return size_;
    }

    [[nodiscard]] bool read(
        const std::uint64_t offset,
        std::uint8_t* const destination,
        const std::size_t byte_count) const noexcept override {
        if (!valid_ || destination == nullptr ||
            byte_count > static_cast<std::size_t>(std::numeric_limits<ULONG>::max()) ||
            offset > static_cast<std::uint64_t>(std::numeric_limits<LONGLONG>::max()) ||
            offset > size_ || static_cast<std::uint64_t>(byte_count) > size_ - offset) {
            return false;
        }

        LARGE_INTEGER requested_position{};
        requested_position.QuadPart = static_cast<LONGLONG>(offset);
        ULARGE_INTEGER actual_position{};
        if (FAILED(stream_->Seek(requested_position, STREAM_SEEK_SET, &actual_position)) ||
            actual_position.QuadPart != offset) {
            return false;
        }

        ULONG bytes_read = 0U;
        return SUCCEEDED(stream_->Read(
                   destination,
                   static_cast<ULONG>(byte_count),
                   &bytes_read)) &&
               bytes_read == byte_count;
    }

private:
    IStream* stream_{nullptr};
    std::uint64_t size_{0};
    bool valid_{false};
};

[[nodiscard]] bool rewind_stream(IStream* const stream) noexcept {
    if (stream == nullptr) {
        return false;
    }
    LARGE_INTEGER beginning{};
    ULARGE_INTEGER actual_position{};
    return SUCCEEDED(stream->Seek(beginning, STREAM_SEEK_SET, &actual_position)) &&
           actual_position.QuadPart == 0U;
}

void discard_samples(WicTiffDecodeResult& result) noexcept {
    std::vector<std::uint16_t>{}.swap(result.image.samples);
}

[[nodiscard]] bool all_u16_values_equal(
    const std::array<std::uint16_t, 8>& values,
    const std::uint8_t count,
    const std::uint16_t expected) noexcept {
    for (std::uint8_t index = 0U; index < count; ++index) {
        if (values[index] != expected) {
            return false;
        }
    }
    return true;
}

[[nodiscard]] bool is_supported_layout(const negaflow::core::TiffProbeInfo& info) noexcept {
    if (info.width > std::numeric_limits<UINT>::max() ||
        info.height > std::numeric_limits<UINT>::max() ||
        info.photometric_interpretation != 2U || info.planar_configuration != 1U ||
        info.orientation != 1U || (info.samples_per_pixel != 3U && info.samples_per_pixel != 4U) ||
        !all_u16_values_equal(info.bits_per_sample, info.bits_per_sample_count, 16U) ||
        !all_u16_values_equal(info.sample_format, info.sample_format_count, 1U) ||
        (info.compression != 1U && info.compression != 5U)) {
        return false;
    }
    if (info.samples_per_pixel == 3U) {
        return info.extra_samples_count == 0U;
    }
    return info.extra_samples_count == 1U &&
           (info.extra_samples[0] == 1U || info.extra_samples[0] == 2U);
}

[[nodiscard]] WicPixelFormat classify_pixel_format(const GUID& format) noexcept {
    if (IsEqualGUID(format, GUID_WICPixelFormat48bppRGB) != 0) {
        return WicPixelFormat::rgb16;
    }
    if (IsEqualGUID(format, GUID_WICPixelFormat64bppRGBA) != 0) {
        return WicPixelFormat::rgba16;
    }
    if (IsEqualGUID(format, GUID_WICPixelFormat64bppPRGBA) != 0) {
        return WicPixelFormat::prgba16;
    }
    if (IsEqualGUID(format, GUID_WICPixelFormat64bppBGRA) != 0) {
        return WicPixelFormat::bgra16;
    }
    if (IsEqualGUID(format, GUID_WICPixelFormat64bppPBGRA) != 0) {
        return WicPixelFormat::pbgra16;
    }
    return WicPixelFormat::unknown;
}

[[nodiscard]] WicTiffDecodeStatus extract_icc_profile(
    IWICImagingFactory* const factory,
    IWICBitmapFrameDecode* const frame,
    const std::uint64_t expected_profile_bytes,
    const WicTiffDecodeLimits& limits,
    WicTiffDecodeResult& result) {
    UINT context_count = 0U;
    HRESULT status = frame->GetColorContexts(0U, nullptr, &context_count);
    if (status == WINCODEC_ERR_UNSUPPORTEDOPERATION && expected_profile_bytes == 0U) {
        return WicTiffDecodeStatus::ok;
    }
    if (FAILED(status) || context_count > limits.max_color_contexts) {
        return WicTiffDecodeStatus::color_context_failed;
    }
    if (context_count == 0U) {
        return expected_profile_bytes == 0U ? WicTiffDecodeStatus::ok
                                            : WicTiffDecodeStatus::color_context_failed;
    }

    std::vector<ComPtr<IWICColorContext>> contexts(context_count);
    std::vector<IWICColorContext*> raw_contexts(context_count, nullptr);
    for (UINT index = 0U; index < context_count; ++index) {
        status = factory->CreateColorContext(&contexts[index]);
        if (FAILED(status)) {
            return WicTiffDecodeStatus::color_context_failed;
        }
        raw_contexts[index] = contexts[index].Get();
    }
    UINT actual_context_count = 0U;
    status = frame->GetColorContexts(context_count, raw_contexts.data(), &actual_context_count);
    if (FAILED(status) || actual_context_count != context_count) {
        return WicTiffDecodeStatus::color_context_failed;
    }

    bool profile_found = false;
    for (const ComPtr<IWICColorContext>& context : contexts) {
        WICColorContextType type = WICColorContextUninitialized;
        status = context->GetType(&type);
        if (FAILED(status)) {
            return WicTiffDecodeStatus::color_context_failed;
        }
        if (type != WICColorContextProfile) {
            continue;
        }
        if (profile_found) {
            return WicTiffDecodeStatus::color_context_failed;
        }
        profile_found = true;

        UINT profile_bytes = 0U;
        status = context->GetProfileBytes(0U, nullptr, &profile_bytes);
        if (FAILED(status) || profile_bytes != expected_profile_bytes ||
            profile_bytes > limits.icc.max_profile_bytes) {
            return WicTiffDecodeStatus::color_context_failed;
        }
        result.image.icc_profile.resize(profile_bytes);
        UINT actual_profile_bytes = 0U;
        status = context->GetProfileBytes(
            profile_bytes,
            result.image.icc_profile.data(),
            &actual_profile_bytes);
        if (FAILED(status) || actual_profile_bytes != profile_bytes) {
            return WicTiffDecodeStatus::color_context_failed;
        }
    }

    if (!profile_found) {
        return expected_profile_bytes == 0U ? WicTiffDecodeStatus::ok
                                            : WicTiffDecodeStatus::color_context_failed;
    }
    const negaflow::color::IccProfileValidationResult validation =
        negaflow::color::validate_icc_profile(result.image.icc_profile, limits.icc);
    result.icc_status = validation.status;
    result.info.icc = validation.info;
    return validation.status == negaflow::color::IccProfileStatus::ok
               ? WicTiffDecodeStatus::ok
               : WicTiffDecodeStatus::invalid_icc_profile;
}

}  // namespace

namespace {

WicTiffDecodeResult decode_tiff_with_wic_impl(
    const std::filesystem::path& path,
    const WicTiffDecodeLimits& limits,
    const WicTiffDecodeControl& control,
    WicTiffRowSink* const row_sink) noexcept {
    WicTiffDecodeResult result{};
    bool sink_started = false;
    const auto complete_sink = [&](const WicTiffDecodeStatus status) noexcept {
        if (sink_started) {
            row_sink->complete(status);
            sink_started = false;
        }
    };
    try {
        if (path.empty() || (row_sink != nullptr && control.rows_per_copy == 0U)) {
            return result;
        }
        if (control.stop_token.stop_requested()) {
            result.status = WicTiffDecodeStatus::cancelled;
            return result;
        }

        const ComApartment apartment{};
        if (apartment.status() == RPC_E_CHANGED_MODE) {
            result.status = WicTiffDecodeStatus::com_apartment_mismatch;
            return result;
        }
        if (FAILED(apartment.status())) {
            result.status = WicTiffDecodeStatus::wic_unavailable;
            return result;
        }

        ComPtr<IStream> stream{};
        HRESULT status = SHCreateStreamOnFileEx(
            path.c_str(),
            STGM_READ | STGM_SHARE_DENY_WRITE,
            FILE_ATTRIBUTE_NORMAL,
            FALSE,
            nullptr,
            &stream);
        if (FAILED(status)) {
            result.status = WicTiffDecodeStatus::stream_open_failed;
            return result;
        }

        const IStreamTiffReader reader{stream.Get()};
        if (!reader.valid()) {
            result.status = WicTiffDecodeStatus::stream_open_failed;
            return result;
        }
        const negaflow::core::TiffProbeResult probe =
            negaflow::core::probe_tiff(reader, limits.probe);
        result.preflight_status = probe.status;
        if (probe.status != negaflow::core::TiffProbeStatus::ok) {
            result.status = WicTiffDecodeStatus::preflight_failed;
            return result;
        }
        if (!is_supported_layout(probe.info)) {
            result.status = WicTiffDecodeStatus::unsupported_layout;
            return result;
        }
        const std::uint64_t channels = probe.info.samples_per_pixel;
        const std::uint64_t bytes_per_pixel = channels * sizeof(std::uint16_t);
        if (probe.info.width > std::numeric_limits<std::uint64_t>::max() / bytes_per_pixel) {
            result.status = WicTiffDecodeStatus::memory_limit_exceeded;
            return result;
        }
        const std::uint64_t expected_stride_bytes = probe.info.width * bytes_per_pixel;
        if (probe.info.height != 0U &&
            expected_stride_bytes >
                std::numeric_limits<std::uint64_t>::max() / probe.info.height) {
            result.status = WicTiffDecodeStatus::memory_limit_exceeded;
            return result;
        }
        const std::uint64_t expected_pixel_bytes =
            expected_stride_bytes * probe.info.height;
        result.info.decoded_pixel_bytes = expected_pixel_bytes;
        result.info.compressed_segment_bytes = probe.info.compressed_segment_bytes;
        if (expected_stride_bytes > std::numeric_limits<UINT>::max() ||
            expected_pixel_bytes > limits.max_decoded_pixel_bytes ||
            expected_pixel_bytes / sizeof(std::uint16_t) >
                static_cast<std::uint64_t>(std::numeric_limits<std::size_t>::max())) {
            result.status = WicTiffDecodeStatus::memory_limit_exceeded;
            return result;
        }

        if (probe.info.compression == 5U) {
            negaflow::core::TiffProbeControl semantic_control{};
            semantic_control.validate_lzw_code_streams = true;
            semantic_control.stop_token = control.stop_token;
            const negaflow::core::TiffProbeResult semantic_probe =
                negaflow::core::probe_tiff(reader, limits.probe, semantic_control);
            result.preflight_status = semantic_probe.status;
            result.info.compressed_bytes_validated =
                semantic_probe.info.compressed_bytes_validated;
            result.info.lzw_code_count = semantic_probe.info.lzw_code_count;
            result.info.lzw_decoded_bytes_validated =
                semantic_probe.info.lzw_decoded_bytes_validated;
            result.info.lzw_code_streams_validated =
                semantic_probe.info.lzw_code_streams_validated;
            if (semantic_probe.status == negaflow::core::TiffProbeStatus::cancelled) {
                result.status = WicTiffDecodeStatus::cancelled;
                return result;
            }
            if (semantic_probe.status != negaflow::core::TiffProbeStatus::ok) {
                result.status = WicTiffDecodeStatus::preflight_failed;
                return result;
            }
        }
        if (control.stop_token.stop_requested()) {
            result.status = WicTiffDecodeStatus::cancelled;
            return result;
        }
        if (!rewind_stream(stream.Get())) {
            result.status = WicTiffDecodeStatus::decoder_initialization_failed;
            return result;
        }

        ComPtr<IWICImagingFactory> factory{};
        status = CoCreateInstance(
            CLSID_WICImagingFactory2,
            nullptr,
            CLSCTX_INPROC_SERVER,
            IID_PPV_ARGS(&factory));
        if (FAILED(status)) {
            status = CoCreateInstance(
                CLSID_WICImagingFactory,
                nullptr,
                CLSCTX_INPROC_SERVER,
                IID_PPV_ARGS(&factory));
        }
        if (FAILED(status)) {
            result.status = WicTiffDecodeStatus::wic_unavailable;
            return result;
        }

        ComPtr<IWICBitmapDecoder> decoder{};
        status = factory->CreateDecoder(
            GUID_ContainerFormatTiff,
            &GUID_VendorMicrosoftBuiltIn,
            &decoder);
        if (FAILED(status) ||
            FAILED(decoder->Initialize(stream.Get(), WICDecodeMetadataCacheOnDemand))) {
            result.status = WicTiffDecodeStatus::decoder_initialization_failed;
            return result;
        }

        ComPtr<IWICBitmapDecoderInfo> decoder_info{};
        CLSID decoder_clsid{};
        GUID container_format{};
        if (FAILED(decoder->GetDecoderInfo(&decoder_info)) ||
            FAILED(decoder_info->GetCLSID(&decoder_clsid)) ||
            FAILED(decoder->GetContainerFormat(&container_format)) ||
            IsEqualGUID(decoder_clsid, CLSID_WICTiffDecoder) == 0 ||
            IsEqualGUID(container_format, GUID_ContainerFormatTiff) == 0) {
            result.status = WicTiffDecodeStatus::unexpected_decoder;
            return result;
        }

        status = decoder->GetFrameCount(&result.info.frame_count);
        if (FAILED(status) || result.info.frame_count != 1U) {
            result.status = WicTiffDecodeStatus::frame_count_unsupported;
            return result;
        }

        ComPtr<IWICBitmapFrameDecode> frame{};
        UINT width = 0U;
        UINT height = 0U;
        GUID source_format{};
        if (FAILED(decoder->GetFrame(0U, &frame)) || FAILED(frame->GetSize(&width, &height)) ||
            FAILED(frame->GetPixelFormat(&source_format))) {
            result.status = WicTiffDecodeStatus::pixel_decode_failed;
            return result;
        }
        if (width != probe.info.width || height != probe.info.height) {
            result.status = WicTiffDecodeStatus::dimension_mismatch;
            return result;
        }
        result.info.source_pixel_format = classify_pixel_format(source_format);

        const bool has_alpha = probe.info.samples_per_pixel == 4U;
        const bool associated_alpha = has_alpha && probe.info.extra_samples[0] == 1U;
        const GUID& target_format = !has_alpha
                                        ? GUID_WICPixelFormat48bppRGB
                                        : associated_alpha ? GUID_WICPixelFormat64bppPRGBA
                                                           : GUID_WICPixelFormat64bppRGBA;
        result.info.output_pixel_format = classify_pixel_format(target_format);
        result.image.width = width;
        result.image.height = height;
        result.image.layout = has_alpha ? DecodedPixelLayout::rgba16
                                        : DecodedPixelLayout::rgb16;
        result.image.alpha_mode = !has_alpha
                                      ? AlphaMode::opaque
                                      : associated_alpha ? AlphaMode::associated
                                                         : AlphaMode::unassociated;

        const std::uint64_t stride_bytes = expected_stride_bytes;
        const std::uint64_t pixel_bytes = expected_pixel_bytes;
        result.image.stride_bytes = static_cast<std::uint32_t>(stride_bytes);

        ComPtr<IWICBitmapSource> pixel_source{};
        if (IsEqualGUID(source_format, target_format) != 0) {
            status = frame.As(&pixel_source);
        } else {
            ComPtr<IWICFormatConverter> converter{};
            BOOL can_convert = FALSE;
            status = factory->CreateFormatConverter(&converter);
            if (SUCCEEDED(status)) {
                status = converter->CanConvert(source_format, target_format, &can_convert);
            }
            if (FAILED(status) || can_convert == FALSE ||
                FAILED(converter->Initialize(
                    frame.Get(),
                    target_format,
                    WICBitmapDitherTypeNone,
                    nullptr,
                    0.0,
                    WICBitmapPaletteTypeCustom))) {
                result.status = WicTiffDecodeStatus::unsupported_pixel_format;
                return result;
            }
            result.info.format_conversion_used = true;
            status = converter.As(&pixel_source);
        }
        if (FAILED(status)) {
            result.status = WicTiffDecodeStatus::unsupported_pixel_format;
            return result;
        }

        const WicTiffDecodeStatus profile_status = extract_icc_profile(
            factory.Get(),
            frame.Get(),
            probe.info.icc_profile_bytes,
            limits,
            result);
        if (profile_status != WicTiffDecodeStatus::ok) {
            result.status = profile_status;
            return result;
        }

        if (control.stop_token.stop_requested()) {
            result.status = WicTiffDecodeStatus::cancelled;
            return result;
        }

        const std::uint64_t maximum_rows_per_copy =
            static_cast<std::uint64_t>(std::numeric_limits<UINT>::max()) /
            stride_bytes;
        if (maximum_rows_per_copy == 0U) {
            result.status = WicTiffDecodeStatus::memory_limit_exceeded;
            return result;
        }
        const bool whole_frame_copy =
            control.rows_per_copy == 0U && pixel_bytes <= std::numeric_limits<UINT>::max();
        if (!whole_frame_copy &&
            (width > static_cast<UINT>(std::numeric_limits<INT>::max()) ||
             height > static_cast<UINT>(std::numeric_limits<INT>::max()))) {
            result.status = WicTiffDecodeStatus::memory_limit_exceeded;
            return result;
        }
        const std::uint64_t requested_rows =
            control.rows_per_copy == 0U ? maximum_rows_per_copy : control.rows_per_copy;
        const std::uint32_t rows_per_copy = static_cast<std::uint32_t>(std::min(
            static_cast<std::uint64_t>(height),
            std::min(requested_rows, maximum_rows_per_copy)));
        if (rows_per_copy == 0U) {
            result.status = WicTiffDecodeStatus::invalid_argument;
            return result;
        }

        if (row_sink != nullptr) {
            const WicTiffFrameView frame_view{
                result.image.width,
                result.image.height,
                result.image.stride_bytes,
                result.image.layout,
                result.image.alpha_mode,
                result.image.icc_profile,
            };
            sink_started = true;
            if (!row_sink->begin(frame_view)) {
                result.status = WicTiffDecodeStatus::row_sink_failed;
                complete_sink(result.status);
                return result;
            }
        }

        if (control.progress_observer != nullptr) {
            control.progress_observer->report({0U, height});
        }
        if (control.stop_token.stop_requested()) {
            result.status = WicTiffDecodeStatus::cancelled;
            complete_sink(result.status);
            return result;
        }

        std::vector<std::uint16_t> row_buffer{};
        if (row_sink == nullptr) {
            result.image.samples.resize(
                static_cast<std::size_t>(pixel_bytes / sizeof(std::uint16_t)));
        } else {
            const std::uint64_t row_buffer_bytes = stride_bytes * rows_per_copy;
            row_buffer.resize(
                static_cast<std::size_t>(row_buffer_bytes / sizeof(std::uint16_t)));
        }
        for (std::uint32_t first_row = 0U; first_row < height;) {
            if (control.stop_token.stop_requested()) {
                discard_samples(result);
                result.status = WicTiffDecodeStatus::cancelled;
                complete_sink(result.status);
                return result;
            }

            const std::uint32_t row_count =
                std::min(rows_per_copy, height - first_row);
            const std::uint64_t copy_bytes = stride_bytes * row_count;
            const std::size_t destination_sample_offset = static_cast<std::size_t>(
                static_cast<std::uint64_t>(first_row) * stride_bytes /
                sizeof(std::uint16_t));
            WICRect rectangle{
                0,
                static_cast<INT>(first_row),
                static_cast<INT>(width),
                static_cast<INT>(row_count),
            };
            std::uint16_t* const destination =
                row_sink == nullptr
                    ? result.image.samples.data() + destination_sample_offset
                    : row_buffer.data();
            status = pixel_source->CopyPixels(
                whole_frame_copy ? nullptr : &rectangle,
                static_cast<UINT>(stride_bytes),
                static_cast<UINT>(copy_bytes),
                reinterpret_cast<BYTE*>(destination));
            if (FAILED(status)) {
                discard_samples(result);
                result.status = WicTiffDecodeStatus::pixel_decode_failed;
                complete_sink(result.status);
                return result;
            }
            ++result.info.copy_operation_count;
            result.info.peak_copy_pixel_bytes =
                std::max(result.info.peak_copy_pixel_bytes, copy_bytes);
            if (control.stop_token.stop_requested()) {
                discard_samples(result);
                result.status = WicTiffDecodeStatus::cancelled;
                complete_sink(result.status);
                return result;
            }

            if (row_sink != nullptr) {
                const WicTiffRowChunk chunk{
                    first_row,
                    row_count,
                    result.image.stride_bytes,
                    std::span<const std::uint16_t>{
                        row_buffer.data(),
                        static_cast<std::size_t>(copy_bytes / sizeof(std::uint16_t))},
                };
                if (!row_sink->write(chunk)) {
                    result.status = control.stop_token.stop_requested()
                                        ? WicTiffDecodeStatus::cancelled
                                        : WicTiffDecodeStatus::row_sink_failed;
                    complete_sink(result.status);
                    return result;
                }
            }

            first_row += row_count;
            result.info.completed_rows = first_row;
            if (control.progress_observer != nullptr) {
                control.progress_observer->report({first_row, height});
            }
        }

        result.status = WicTiffDecodeStatus::ok;
        complete_sink(result.status);
        return result;
    } catch (const std::bad_alloc&) {
        discard_samples(result);
        result.status = WicTiffDecodeStatus::allocation_failed;
        complete_sink(result.status);
        return result;
    } catch (...) {
        discard_samples(result);
        result.status = WicTiffDecodeStatus::pixel_decode_failed;
        complete_sink(result.status);
        return result;
    }
}

}  // namespace

WicTiffDecodeResult decode_tiff_with_wic(
    const std::filesystem::path& path,
    const WicTiffDecodeLimits& limits,
    const WicTiffDecodeControl& control) noexcept {
    return decode_tiff_with_wic_impl(path, limits, control, nullptr);
}

WicTiffDecodeResult decode_tiff_rows_with_wic(
    const std::filesystem::path& path,
    WicTiffRowSink& sink,
    const WicTiffDecodeLimits& limits,
    const WicTiffDecodeControl& control) noexcept {
    return decode_tiff_with_wic_impl(path, limits, control, &sink);
}

const char* wic_tiff_decode_status_name(const WicTiffDecodeStatus status) noexcept {
    switch (status) {
        case WicTiffDecodeStatus::ok:
            return "ok";
        case WicTiffDecodeStatus::invalid_argument:
            return "invalid_argument";
        case WicTiffDecodeStatus::preflight_failed:
            return "tiff_preflight_failed";
        case WicTiffDecodeStatus::unsupported_layout:
            return "unsupported_tiff_layout";
        case WicTiffDecodeStatus::com_apartment_mismatch:
            return "com_apartment_mismatch";
        case WicTiffDecodeStatus::wic_unavailable:
            return "wic_unavailable";
        case WicTiffDecodeStatus::stream_open_failed:
            return "wic_stream_open_failed";
        case WicTiffDecodeStatus::decoder_initialization_failed:
            return "wic_decoder_initialization_failed";
        case WicTiffDecodeStatus::unexpected_decoder:
            return "unexpected_wic_decoder";
        case WicTiffDecodeStatus::frame_count_unsupported:
            return "unsupported_frame_count";
        case WicTiffDecodeStatus::dimension_mismatch:
            return "wic_dimension_mismatch";
        case WicTiffDecodeStatus::unsupported_pixel_format:
            return "unsupported_wic_pixel_format";
        case WicTiffDecodeStatus::color_context_failed:
            return "wic_color_context_failed";
        case WicTiffDecodeStatus::invalid_icc_profile:
            return "invalid_icc_profile";
        case WicTiffDecodeStatus::memory_limit_exceeded:
            return "decoded_pixel_memory_limit_exceeded";
        case WicTiffDecodeStatus::allocation_failed:
            return "decoded_pixel_allocation_failed";
        case WicTiffDecodeStatus::pixel_decode_failed:
            return "wic_pixel_decode_failed";
        case WicTiffDecodeStatus::row_sink_failed:
            return "wic_row_sink_failed";
        case WicTiffDecodeStatus::cancelled:
            return "cancelled";
    }
    return "unknown_wic_tiff_decode_status";
}

const char* wic_pixel_format_name(const WicPixelFormat format) noexcept {
    switch (format) {
        case WicPixelFormat::unknown:
            return "unknown";
        case WicPixelFormat::rgb16:
            return "48bpp_rgb";
        case WicPixelFormat::rgba16:
            return "64bpp_rgba";
        case WicPixelFormat::prgba16:
            return "64bpp_prgba";
        case WicPixelFormat::bgra16:
            return "64bpp_bgra";
        case WicPixelFormat::pbgra16:
            return "64bpp_pbgra";
    }
    return "unknown";
}

}  // namespace negaflow::imageio
