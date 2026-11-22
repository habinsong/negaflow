#include "negaflow/output/print_sheet_publish.h"
#include "negaflow/output/dng_linear_export.h"

#include "atomic_output_file.h"
#include "wic_srgb16_support.h"
#include "../imaging/icm_rgb16_parallel.h"
#include "negaflow/color/output_color_space.h"
#include "negaflow/color/srgb_transfer.h"
#include "negaflow/core/parallel_rows.h"

#include <Windows.h>
#include <Shlwapi.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <memory>
#include <new>
#include <system_error>
#include <vector>

namespace negaflow::output {
namespace {

using Microsoft::WRL::ComPtr;

// sRGB 코드값으로 합성한 판을 고른 Delivery 색공간의 코드값으로 옮깁니다. 판의 색은 모두
// sRGB 안이고 Display P3·Adobe RGB 는 sRGB 를 품으므로 자를 것이 없습니다. 그래서 ICM 표
// 보간 없이 행렬과 전달 곡선으로 정확히 옮깁니다(macOS ColorSync 의 행렬 변환과 같은 값).
// 16비트 sRGB 해독은 65536 칸 표로 하고, 행 블록마다 나눠 옮깁니다.
[[nodiscard]] bool convert_srgb_page_to_space(
    const std::span<const std::uint16_t> page,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_bytes,
    const negaflow::color::OutputColorSpace space,
    std::vector<std::uint16_t>& converted) noexcept {
    std::vector<float> decode{};
    try {
        decode.resize(65536U);
        converted.resize(static_cast<std::size_t>(width) * 3U * height);
    } catch (const std::bad_alloc&) {
        return false;
    }
    for (std::size_t code = 0U; code < decode.size(); ++code) {
        decode[code] = negaflow::color::srgb_encoded_to_linear(
            static_cast<float>(code) / 65535.0F);
    }
    const negaflow::color::ColorMatrix matrix = negaflow::color::linear_srgb_to(space);
    const std::size_t source_row_samples = stride_bytes / 2U;
    const std::size_t target_row_samples = static_cast<std::size_t>(width) * 3U;
    negaflow::core::for_each_row_block(
        height,
        static_cast<std::uint64_t>(width) * height * 3U,
        [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
            for (std::uint32_t y = first_row; y < first_row + row_count; ++y) {
                const std::uint16_t* const in = page.data() + (y * source_row_samples);
                std::uint16_t* const out = converted.data() + (y * target_row_samples);
                for (std::uint32_t x = 0U; x < width; ++x) {
                    const std::array<float, 3> linear{
                        decode[in[x * 3U]], decode[in[(x * 3U) + 1U]], decode[in[(x * 3U) + 2U]]};
                    for (std::size_t row = 0U; row < 3U; ++row) {
                        const float value = (matrix[row * 3U] * linear[0]) +
                                            (matrix[(row * 3U) + 1U] * linear[1]) +
                                            (matrix[(row * 3U) + 2U] * linear[2]);
                        const float encoded = negaflow::color::encode_output_component(
                            std::clamp(value, 0.0F, 1.0F), space);
                        out[(x * 3U) + row] = static_cast<std::uint16_t>(
                            std::lround(std::clamp(encoded, 0.0F, 1.0F) * 65535.0F));
                    }
                }
            }
        });
    return true;
}

[[nodiscard]] PrintSheetPublishStatus map_atomic_status(
    const detail::AtomicOutputStatus status) noexcept {
    switch (status) {
        case detail::AtomicOutputStatus::ok:
            return PrintSheetPublishStatus::ok;
        case detail::AtomicOutputStatus::destination_exists:
            return PrintSheetPublishStatus::destination_exists;
        case detail::AtomicOutputStatus::flush_failed:
            return PrintSheetPublishStatus::flush_failed;
        case detail::AtomicOutputStatus::published_file_invalid:
            return PrintSheetPublishStatus::published_file_invalid;
        case detail::AtomicOutputStatus::publish_failed:
            return PrintSheetPublishStatus::publish_failed;
        case detail::AtomicOutputStatus::allocation_failed:
        case detail::AtomicOutputStatus::invalid_path:
        case detail::AtomicOutputStatus::destination_query_failed:
        case detail::AtomicOutputStatus::parent_unavailable:
        case detail::AtomicOutputStatus::staging_create_failed:
            return PrintSheetPublishStatus::staging_create_failed;
    }
    return PrintSheetPublishStatus::staging_create_failed;
}

[[nodiscard]] bool write_option(
    IPropertyBag2* const options,
    const wchar_t* const name,
    const VARIANT& value,
    std::uint32_t& native_error_code) noexcept {
    PROPBAG2 option{};
    option.dwType = PROPBAG2_TYPE_DATA;
    option.vt = value.vt;
    option.pstrName = const_cast<wchar_t*>(name);
    const HRESULT status = options->Write(1U, &option, const_cast<VARIANT*>(&value));
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return false;
    }
    return true;
}

[[nodiscard]] const GUID& container_for(const PrintSheetFormat format) noexcept {
    switch (format) {
        case PrintSheetFormat::tiff16:
            return GUID_ContainerFormatTiff;
        case PrintSheetFormat::jpeg8:
            return GUID_ContainerFormatJpeg;
        case PrintSheetFormat::png16:
        default:
            return GUID_ContainerFormatPng;
    }
}

[[nodiscard]] const CLSID& encoder_class_for(const PrintSheetFormat format) noexcept {
    switch (format) {
        case PrintSheetFormat::tiff16:
            return CLSID_WICTiffEncoder;
        case PrintSheetFormat::jpeg8:
            return CLSID_WICJpegEncoder;
        case PrintSheetFormat::png16:
        default:
            return CLSID_WICPngEncoder;
    }
}

[[nodiscard]] bool map_tiff_compression(
    const PrintSheetTiffCompression compression,
    BYTE& wic_value) noexcept {
    switch (compression) {
        case PrintSheetTiffCompression::none:
            wic_value = static_cast<BYTE>(WICTiffCompressionNone);
            return true;
        case PrintSheetTiffCompression::lzw:
            wic_value = static_cast<BYTE>(WICTiffCompressionLZW);
            return true;
        case PrintSheetTiffCompression::deflate:
            wic_value = static_cast<BYTE>(WICTiffCompressionZIP);
            return true;
    }
    return false;
}

// 16-bit 판은 그대로 씁니다. JPEG 만 8-bit 로 내려가며, 그때도 오차 확산으로 떨어뜨립니다 -
// 현상 내보내기의 JPEG 경로와 같은 규칙입니다.
[[nodiscard]] PrintSheetPublishStatus encode_sheet(
    IWICImagingFactory* const factory,
    IStream* const stream,
    const std::span<const std::uint16_t> page,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_bytes,
    IWICColorContext* const color_context,
    const PrintSheetFormat format,
    const PrintSheetPublishLimits& limits,
    std::uint32_t& native_error_code) noexcept {
    ComPtr<IWICBitmapEncoder> encoder{};
    HRESULT status = factory->CreateEncoder(
        container_for(format),
        &GUID_VendorMicrosoft,
        &encoder);
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return PrintSheetPublishStatus::encoder_initialization_failed;
    }
    ComPtr<IWICBitmapEncoderInfo> encoder_info{};
    CLSID chosen{};
    status = encoder->GetEncoderInfo(&encoder_info);
    if (SUCCEEDED(status)) {
        status = encoder_info->GetCLSID(&chosen);
    }
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return PrintSheetPublishStatus::encoder_initialization_failed;
    }
    if (IsEqualGUID(chosen, encoder_class_for(format)) == FALSE) {
        return PrintSheetPublishStatus::unexpected_encoder;
    }

    status = encoder->Initialize(stream, WICBitmapEncoderNoCache);
    ComPtr<IWICBitmapFrameEncode> frame{};
    ComPtr<IPropertyBag2> options{};
    if (SUCCEEDED(status)) {
        status = encoder->CreateNewFrame(&frame, &options);
    }
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return PrintSheetPublishStatus::encoder_initialization_failed;
    }

    if (format == PrintSheetFormat::jpeg8) {
        VARIANT quality{};
        quality.vt = VT_R4;
        quality.fltVal = std::clamp(limits.jpeg_quality, 0.0F, 1.0F);
        if (!write_option(options.Get(), L"ImageQuality", quality, native_error_code)) {
            return PrintSheetPublishStatus::encoder_initialization_failed;
        }
        // 크로마 서브샘플링은 현상 JPEG 와 같은 규칙입니다 — 품질 0.95 이상이면 4:4:4, 아래는
        // 4:2:0(macOS `ExportEngine.encodedJPEGQuality`). 앞 판은 인화 판에만 이 값을 주지 않아
        // 고품질 판의 채도 높은 캡션·필름 띠 가장자리가 반 해상도 색으로 번졌습니다.
        VARIANT subsampling{};
        subsampling.vt = VT_UI1;
        subsampling.bVal = quality.fltVal >= 0.95F
            ? static_cast<BYTE>(WICJpegYCrCbSubsampling444)
            : static_cast<BYTE>(WICJpegYCrCbSubsampling420);
        if (!write_option(options.Get(), L"JpegYCrCbSubsampling", subsampling, native_error_code)) {
            return PrintSheetPublishStatus::encoder_initialization_failed;
        }
    } else if (format == PrintSheetFormat::tiff16) {
        BYTE compression = 0;
        if (!map_tiff_compression(limits.tiff_compression, compression)) {
            return PrintSheetPublishStatus::invalid_format;
        }
        VARIANT method{};
        method.vt = VT_UI1;
        method.bVal = compression;
        if (!write_option(
                options.Get(), L"TiffCompressionMethod", method, native_error_code)) {
            return PrintSheetPublishStatus::encoder_initialization_failed;
        }
    }
    status = frame->Initialize(options.Get());
    if (SUCCEEDED(status)) {
        status = frame->SetSize(width, height);
    }
    if (SUCCEEDED(status) && limits.output_dpi != 0U) {
        status = frame->SetResolution(
            static_cast<double>(limits.output_dpi),
            static_cast<double>(limits.output_dpi));
    }
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return PrintSheetPublishStatus::encoder_initialization_failed;
    }

    const WICPixelFormatGUID requested = format == PrintSheetFormat::jpeg8
        ? GUID_WICPixelFormat24bppBGR
        : GUID_WICPixelFormat48bppRGB;
    WICPixelFormatGUID pixel_format = requested;
    status = frame->SetPixelFormat(&pixel_format);
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return PrintSheetPublishStatus::encoder_initialization_failed;
    }
    if (IsEqualGUID(pixel_format, requested) == FALSE) {
        return PrintSheetPublishStatus::pixel_format_coerced;
    }

    // **프로파일은 화소보다 먼저 겁니다.** 인코더에 따라 나중에 들어온 색 문맥을 조용히
    // 버리는 것이 있습니다 - 그러면 픽셀은 랩 공간인데 파일은 sRGB 로 읽힙니다.
    IWICColorContext* contexts[]{color_context};
    status = frame->SetColorContexts(1U, contexts);
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return PrintSheetPublishStatus::encoder_initialization_failed;
    }

    const std::uint64_t bytes_64 = static_cast<std::uint64_t>(stride_bytes) * height;
    if (bytes_64 > static_cast<std::uint64_t>(std::numeric_limits<UINT>::max())) {
        return PrintSheetPublishStatus::encode_failed;
    }
    BYTE* const samples =
        reinterpret_cast<BYTE*>(const_cast<std::uint16_t*>(page.data()));
    if (format == PrintSheetFormat::jpeg8) {
        ComPtr<IWICBitmap> source{};
        status = factory->CreateBitmapFromMemory(
            width,
            height,
            GUID_WICPixelFormat48bppRGB,
            stride_bytes,
            static_cast<UINT>(bytes_64),
            samples,
            &source);
        ComPtr<IWICFormatConverter> dithered{};
        if (SUCCEEDED(status)) {
            status = factory->CreateFormatConverter(&dithered);
        }
        if (SUCCEEDED(status)) {
            status = dithered->Initialize(
                source.Get(),
                GUID_WICPixelFormat24bppBGR,
                WICBitmapDitherTypeErrorDiffusion,
                nullptr,
                0.0,
                WICBitmapPaletteTypeCustom);
        }
        if (SUCCEEDED(status)) {
            status = frame->WriteSource(dithered.Get(), nullptr);
        }
    } else {
        status = frame->WritePixels(
            height,
            stride_bytes,
            static_cast<UINT>(bytes_64),
            samples);
    }
    if (SUCCEEDED(status)) {
        status = frame->Commit();
    }
    if (SUCCEEDED(status)) {
        status = encoder->Commit();
    }
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return PrintSheetPublishStatus::encode_failed;
    }
    return PrintSheetPublishStatus::ok;
}

void discard_staging(
    detail::AtomicOutputFile* const output,
    PrintSheetPublishResult& result) noexcept {
    if (output != nullptr) {
        output->discard(result.cleanup_error_code);
    }
}

}  // namespace

PrintSheetPublishResult publish_print_sheet(
    const std::span<const std::uint16_t> page,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_bytes,
    const std::filesystem::path& destination,
    const PrintSheetFormat format,
    const PrintSheetPublishLimits& limits) noexcept {
    PrintSheetPublishResult result{};
    if (format != PrintSheetFormat::png16 && format != PrintSheetFormat::tiff16 &&
        format != PrintSheetFormat::jpeg8 && format != PrintSheetFormat::dng16) {
        result.status = PrintSheetPublishStatus::invalid_format;
        return result;
    }
    if (width == 0U || height == 0U ||
        width > static_cast<std::uint32_t>(std::numeric_limits<INT>::max()) ||
        height > static_cast<std::uint32_t>(std::numeric_limits<INT>::max())) {
        result.status = PrintSheetPublishStatus::invalid_dimensions;
        return result;
    }
    const std::uint64_t row_bytes = static_cast<std::uint64_t>(width) * 3ULL * 2ULL;
    if (stride_bytes < row_bytes) {
        result.status = PrintSheetPublishStatus::buffer_size_mismatch;
        return result;
    }
    const std::uint64_t needed_bytes =
        static_cast<std::uint64_t>(stride_bytes) * static_cast<std::uint64_t>(height);
    if (needed_bytes > limits.max_encoded_pixel_bytes) {
        result.status = PrintSheetPublishStatus::memory_limit_exceeded;
        return result;
    }
    if (page.size_bytes() < needed_bytes) {
        result.status = PrintSheetPublishStatus::buffer_size_mismatch;
        return result;
    }

    result.info.width = width;
    result.info.height = height;
    result.info.bits_per_sample = format == PrintSheetFormat::jpeg8 ? 8U : 16U;
    result.info.output_dpi = limits.output_dpi;

    if (format == PrintSheetFormat::dng16) {
        // DNG 인화 판은 sRGB 코드값으로 합성하고, 파일 경계에서 선형 RGB로 변환한다.
        if (!limits.output_icc_profile.empty()) {
            result.status = PrintSheetPublishStatus::destination_profile_invalid;
            return result;
        }
        DngExportLimits dng_limits{};
        dng_limits.output_dpi = limits.output_dpi;
        const auto dng = export_srgb16_to_dng16(page, width, height, stride_bytes / 2U, destination, dng_limits);
        result.info.artifact_bytes = dng.info.artifact_bytes;
        result.info.published = dng.info.published;
        result.native_error_code = dng.native_error_code;
        result.cleanup_error_code = dng.cleanup_error_code;
        switch (dng.status) {
            case DngExportStatus::ok: result.status = PrintSheetPublishStatus::ok; break;
            case DngExportStatus::destination_exists: result.status = PrintSheetPublishStatus::destination_exists; break;
            case DngExportStatus::size_limit_exceeded:
            case DngExportStatus::allocation_failed: result.status = PrintSheetPublishStatus::memory_limit_exceeded; break;
            case DngExportStatus::staging_create_failed: result.status = PrintSheetPublishStatus::staging_create_failed; break;
            case DngExportStatus::flush_failed: result.status = PrintSheetPublishStatus::flush_failed; break;
            case DngExportStatus::publish_failed: result.status = PrintSheetPublishStatus::publish_failed; break;
            case DngExportStatus::published_file_invalid:
            case DngExportStatus::structure_verification_failed: result.status = PrintSheetPublishStatus::published_file_invalid; break;
            default: result.status = PrintSheetPublishStatus::encode_failed; break;
        }
        return result;
    }

    const detail::ComApartment apartment{};
    if (apartment.status() == RPC_E_CHANGED_MODE) {
        result.status = PrintSheetPublishStatus::com_apartment_mismatch;
        result.native_error_code = static_cast<std::uint32_t>(apartment.status());
        return result;
    }
    if (FAILED(apartment.status())) {
        result.status = PrintSheetPublishStatus::wic_unavailable;
        result.native_error_code = static_cast<std::uint32_t>(apartment.status());
        return result;
    }
    ComPtr<IWICImagingFactory2> factory{};
    if (!detail::create_wic_factory(factory, result.native_error_code)) {
        result.status = PrintSheetPublishStatus::wic_unavailable;
        return result;
    }

    ComPtr<IWICColorContext> color_context{};
    std::vector<std::uint8_t> profile_bytes{};
    // 인화소 ICC 가 있으면 그것이 이기고(`load_output_color_context` 가 그 바이트를 박습니다),
    // 없으면 고른 Delivery 색공간의 프로파일을 박습니다.
    switch (detail::load_output_color_context(
        factory.Get(),
        limits.output_color_space,
        limits.max_color_profile_bytes,
        color_context,
        profile_bytes,
        result.native_error_code,
        false,
        limits.output_icc_profile)) {
        case detail::StandardSrgbStatus::ok:
            break;
        case detail::StandardSrgbStatus::unavailable:
            result.status = PrintSheetPublishStatus::destination_profile_unavailable;
            return result;
        case detail::StandardSrgbStatus::invalid:
            result.status = PrintSheetPublishStatus::destination_profile_invalid;
            return result;
    }
    result.info.color_profile_bytes = static_cast<std::uint32_t>(profile_bytes.size());

    // **인화소 ICC 는 다 합성한 판 전체에 한 번 겁니다.** 판은 sRGB 코드값으로 합성됩니다 —
    // 사진도, 바탕·필름 띠·캡션·워터마크도. 앞 판은 사진만 먼저 프린터 RGB 로 옮긴 뒤 나머지를
    // sRGB 값 그대로 그 위에 칠해서, 회색 바탕과 필름 띠가 프린터 공간에서 다른 색으로
    // 읽혔습니다. macOS 도 판을 한 장으로 합성한 뒤 그 결과를 출력 공간으로 렌더합니다.
    std::span<const std::uint16_t> published_page = page;
    std::uint32_t published_stride = stride_bytes;
    std::vector<std::uint16_t> translated{};
    if (!limits.output_icc_profile.empty()) {
        const std::uint64_t packed_stride = row_bytes;
        try {
            translated.resize(static_cast<std::size_t>(packed_stride / 2U) * height);
        } catch (const std::bad_alloc&) {
            result.status = PrintSheetPublishStatus::memory_limit_exceeded;
            return result;
        }
        // 판 한 장이 수십 MP 라 코어마다 나눠 옮깁니다.
        negaflow::imaging::detail::ParallelIcmRgb16Transform icc{};
        if (icc.initialize_to_profile(limits.output_icc_profile, result.native_error_code) !=
                negaflow::imaging::ScannerToWorkingStatus::ok ||
            icc.translate(
                page.data(),
                width,
                height,
                stride_bytes,
                translated.data(),
                static_cast<std::uint32_t>(packed_stride),
                result.native_error_code) != negaflow::imaging::ScannerToWorkingStatus::ok) {
            result.status = PrintSheetPublishStatus::destination_profile_invalid;
            return result;
        }
        published_page = translated;
        published_stride = static_cast<std::uint32_t>(packed_stride);
    } else if (limits.output_color_space != negaflow::color::OutputColorSpace::srgb) {
        // Delivery 가 P3·Adobe RGB 면 판 전체를 그 공간으로 옮깁니다(JPEG 포함). 앞 판은 이
        // 값을 무시하고 늘 sRGB 로 냈습니다.
        if (!convert_srgb_page_to_space(
                page, width, height, stride_bytes, limits.output_color_space, translated)) {
            result.status = PrintSheetPublishStatus::memory_limit_exceeded;
            return result;
        }
        published_page = translated;
        published_stride = static_cast<std::uint32_t>(row_bytes);
    }

    std::unique_ptr<detail::AtomicOutputFile> output{};
    const detail::AtomicOutputStatus create_status = detail::AtomicOutputFile::create(
        destination,
        output,
        result.native_error_code);
    if (create_status != detail::AtomicOutputStatus::ok) {
        result.status = map_atomic_status(create_status);
        return result;
    }

    result.status = encode_sheet(
        factory.Get(),
        output->stream(),
        published_page,
        width,
        height,
        published_stride,
        color_context.Get(),
        format,
        limits,
        result.native_error_code);
    if (result.status != PrintSheetPublishStatus::ok) {
        discard_staging(output.get(), result);
        return result;
    }
    const detail::AtomicOutputStatus flush_status =
        output->close_and_flush(result.native_error_code);
    if (flush_status != detail::AtomicOutputStatus::ok) {
        result.status = map_atomic_status(flush_status);
        discard_staging(output.get(), result);
        return result;
    }

    std::error_code size_error{};
    const std::uintmax_t written_bytes =
        std::filesystem::file_size(output->staging_path(), size_error);
    if (size_error) {
        result.status = PrintSheetPublishStatus::published_file_invalid;
        discard_staging(output.get(), result);
        return result;
    }
    result.info.artifact_bytes = static_cast<std::uint64_t>(written_bytes);

    const detail::AtomicOutputStatus publish_status = output->publish(
        result.info.artifact_bytes,
        result.native_error_code);
    if (publish_status != detail::AtomicOutputStatus::ok) {
        result.status = map_atomic_status(publish_status);
        discard_staging(output.get(), result);
        return result;
    }
    result.info.published = true;
    result.status = PrintSheetPublishStatus::ok;
    return result;
}

const char* print_sheet_publish_status_name(
    const PrintSheetPublishStatus status) noexcept {
    switch (status) {
        case PrintSheetPublishStatus::ok:
            return "ok";
        case PrintSheetPublishStatus::invalid_dimensions:
            return "invalid_dimensions";
        case PrintSheetPublishStatus::invalid_format:
            return "invalid_format";
        case PrintSheetPublishStatus::buffer_size_mismatch:
            return "buffer_size_mismatch";
        case PrintSheetPublishStatus::memory_limit_exceeded:
            return "memory_limit_exceeded";
        case PrintSheetPublishStatus::com_apartment_mismatch:
            return "com_apartment_mismatch";
        case PrintSheetPublishStatus::wic_unavailable:
            return "wic_unavailable";
        case PrintSheetPublishStatus::destination_profile_unavailable:
            return "destination_profile_unavailable";
        case PrintSheetPublishStatus::destination_profile_invalid:
            return "destination_profile_invalid";
        case PrintSheetPublishStatus::destination_exists:
            return "destination_exists";
        case PrintSheetPublishStatus::staging_create_failed:
            return "staging_create_failed";
        case PrintSheetPublishStatus::encoder_initialization_failed:
            return "encoder_initialization_failed";
        case PrintSheetPublishStatus::unexpected_encoder:
            return "unexpected_encoder";
        case PrintSheetPublishStatus::pixel_format_coerced:
            return "pixel_format_coerced";
        case PrintSheetPublishStatus::encode_failed:
            return "encode_failed";
        case PrintSheetPublishStatus::flush_failed:
            return "flush_failed";
        case PrintSheetPublishStatus::publish_failed:
            return "publish_failed";
        case PrintSheetPublishStatus::published_file_invalid:
            return "published_file_invalid";
    }
    return "unknown_print_sheet_publish_status";
}

}  // namespace negaflow::output
