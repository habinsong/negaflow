#include "negaflow/output/print_sheet_publish.h"

#include "atomic_output_file.h"
#include "wic_srgb16_support.h"

#include <Windows.h>
#include <Shlwapi.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <algorithm>
#include <cstdint>
#include <limits>
#include <memory>
#include <new>
#include <system_error>
#include <vector>

namespace negaflow::output {
namespace {

using Microsoft::WRL::ComPtr;

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
        format != PrintSheetFormat::jpeg8) {
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
    switch (detail::load_output_color_context(
        factory.Get(),
        negaflow::color::OutputColorSpace::srgb,
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
        page,
        width,
        height,
        stride_bytes,
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
