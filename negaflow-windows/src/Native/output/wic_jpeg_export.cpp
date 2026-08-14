#include "negaflow/output/wic_jpeg_export.h"

#include "atomic_output_file.h"
#include "wic_srgb16_support.h"

#include <Windows.h>
#include <Shlwapi.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <limits>
#include <new>
#include <vector>

namespace negaflow::output {
namespace {

using Microsoft::WRL::ComPtr;

struct JpegStructure final {
    std::uint32_t width{0U};
    std::uint32_t height{0U};
    std::uint8_t components{0U};
    std::uint8_t chroma_subsampling{0U};
};

[[nodiscard]] WicJpegExportStatus map_atomic_status(
    const detail::AtomicOutputStatus status) noexcept {
    switch (status) {
        case detail::AtomicOutputStatus::ok:
            return WicJpegExportStatus::ok;
        case detail::AtomicOutputStatus::destination_exists:
            return WicJpegExportStatus::destination_exists;
        case detail::AtomicOutputStatus::flush_failed:
            return WicJpegExportStatus::flush_failed;
        case detail::AtomicOutputStatus::published_file_invalid:
            return WicJpegExportStatus::published_file_invalid;
        case detail::AtomicOutputStatus::publish_failed:
            return WicJpegExportStatus::publish_failed;
        case detail::AtomicOutputStatus::allocation_failed:
            return WicJpegExportStatus::allocation_failed;
        case detail::AtomicOutputStatus::invalid_path:
        case detail::AtomicOutputStatus::destination_query_failed:
        case detail::AtomicOutputStatus::parent_unavailable:
        case detail::AtomicOutputStatus::staging_create_failed:
            return WicJpegExportStatus::staging_create_failed;
    }
    return WicJpegExportStatus::staging_create_failed;
}

void discard_staging(
    detail::AtomicOutputFile* const output,
    WicJpegExportResult& result) noexcept {
    if (output != nullptr) {
        output->discard(result.cleanup_error_code);
    }
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

[[nodiscard]] WicJpegExportStatus encode_jpeg(
    IWICImagingFactory* const factory,
    IStream* const stream,
    const Srgb16Image& image,
    IWICColorContext* const color_context,
    const float quality,
    const std::uint32_t dpi,
    const std::uint8_t expected_subsampling,
    const ExportMetadataPolicy metadata_policy,
    const ExportMetadataFields& metadata,
    std::uint32_t& native_error_code) noexcept {
    ComPtr<IWICBitmapEncoder> encoder{};
    HRESULT status = factory->CreateEncoder(
        GUID_ContainerFormatJpeg,
        &GUID_VendorMicrosoft,
        &encoder);
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicJpegExportStatus::encoder_initialization_failed;
    }
    ComPtr<IWICBitmapEncoderInfo> encoder_info{};
    CLSID encoder_class{};
    status = encoder->GetEncoderInfo(&encoder_info);
    if (SUCCEEDED(status)) {
        status = encoder_info->GetCLSID(&encoder_class);
    }
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicJpegExportStatus::encoder_initialization_failed;
    }
    if (IsEqualGUID(encoder_class, CLSID_WICJpegEncoder) == FALSE) {
        return WicJpegExportStatus::unexpected_encoder;
    }

    status = encoder->Initialize(stream, WICBitmapEncoderNoCache);
    ComPtr<IWICBitmapFrameEncode> frame{};
    ComPtr<IPropertyBag2> options{};
    if (SUCCEEDED(status)) {
        status = encoder->CreateNewFrame(&frame, &options);
    }
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicJpegExportStatus::encoder_initialization_failed;
    }

    VARIANT quality_value{};
    quality_value.vt = VT_R4;
    quality_value.fltVal = quality;
    VARIANT subsampling_value{};
    subsampling_value.vt = VT_UI1;
    subsampling_value.bVal = expected_subsampling;
    if (!write_option(options.Get(), L"ImageQuality", quality_value, native_error_code) ||
        !write_option(
            options.Get(), L"JpegYCrCbSubsampling", subsampling_value, native_error_code)) {
        return WicJpegExportStatus::encoder_initialization_failed;
    }
    status = frame->Initialize(options.Get());
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicJpegExportStatus::encoder_initialization_failed;
    }
    status = frame->SetSize(image.width, image.height);
    if (SUCCEEDED(status) && dpi != 0U) {
        status = frame->SetResolution(static_cast<double>(dpi), static_cast<double>(dpi));
    }
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicJpegExportStatus::resolution_configuration_failed;
    }
    WICPixelFormatGUID pixel_format = GUID_WICPixelFormat24bppBGR;
    status = frame->SetPixelFormat(&pixel_format);
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicJpegExportStatus::encoder_initialization_failed;
    }
    if (IsEqualGUID(pixel_format, GUID_WICPixelFormat24bppBGR) == FALSE) {
        return WicJpegExportStatus::pixel_format_coerced;
    }
    // **픽셀보다 먼저** 쓴다. WIC 의 JPEG 인코더는 WriteSource 뒤에 들어온 메타데이터를
    // 조용히 버린다 — TIFF 는 받아들여서 이 차이를 실파일로 확인하기 전에는 보이지 않았다.
    // 실패하면 게시를 접는다: 고른 정책이 무시된 파일을 내보내지 않는다.
    const ExportMetadataStatus metadata_status = write_export_metadata(
        frame.Get(),
        ExportMetadataContainer::jpeg,
        metadata_policy,
        metadata,
        native_error_code);
    if (metadata_status == ExportMetadataStatus::write_failed) {
        return WicJpegExportStatus::encode_failed;
    }

    IWICColorContext* contexts[]{color_context};
    status = frame->SetColorContexts(1U, contexts);
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicJpegExportStatus::encoder_initialization_failed;
    }

    const std::uint64_t bytes_64 =
        static_cast<std::uint64_t>(image.stride_bytes) * image.height;
    if (bytes_64 > std::numeric_limits<UINT>::max()) {
        return WicJpegExportStatus::encode_failed;
    }
    ComPtr<IWICBitmap> source{};
    status = factory->CreateBitmapFromMemory(
        image.width,
        image.height,
        GUID_WICPixelFormat48bppRGB,
        image.stride_bytes,
        static_cast<UINT>(bytes_64),
        reinterpret_cast<BYTE*>(const_cast<std::uint16_t*>(image.samples.data())),
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
    if (SUCCEEDED(status)) {
        status = frame->Commit();
    }
    if (SUCCEEDED(status)) {
        status = encoder->Commit();
    }
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicJpegExportStatus::encode_failed;
    }
    return WicJpegExportStatus::ok;
}

[[nodiscard]] bool inspect_jpeg_structure(
    const std::filesystem::path& path,
    const std::uint64_t maximum_file_bytes,
    JpegStructure& result) noexcept {
    std::error_code error{};
    const std::uint64_t file_bytes = std::filesystem::file_size(path, error);
    if (error || file_bytes < 4U || file_bytes > maximum_file_bytes ||
        file_bytes > static_cast<std::uint64_t>(std::numeric_limits<std::size_t>::max())) {
        return false;
    }
    std::ifstream input(path, std::ios::binary);
    std::vector<std::uint8_t> bytes(
        static_cast<std::size_t>(file_bytes));
    input.read(reinterpret_cast<char*>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
    if (!input || bytes[0] != 0xFFU || bytes[1] != 0xD8U) {
        return false;
    }
    for (std::size_t index = 2U; index + 1U < bytes.size();) {
        if (bytes[index] != 0xFFU) {
            ++index;
            continue;
        }
        while (index < bytes.size() && bytes[index] == 0xFFU) {
            ++index;
        }
        if (index >= bytes.size()) {
            return false;
        }
        const std::uint8_t marker = bytes[index++];
        if (marker == 0xD9U || marker == 0xDAU) {
            return false;
        }
        if (marker == 0x01U || (marker >= 0xD0U && marker <= 0xD7U)) {
            continue;
        }
        if (index + 2U > bytes.size()) {
            return false;
        }
        const std::uint16_t segment_size = static_cast<std::uint16_t>(
            (static_cast<std::uint16_t>(bytes[index]) << 8U) | bytes[index + 1U]);
        if (segment_size < 2U || index + segment_size > bytes.size()) {
            return false;
        }
        if ((marker == 0xC0U || marker == 0xC1U || marker == 0xC2U) &&
            segment_size >= 11U) {
            const std::size_t data = index + 2U;
            result.height = static_cast<std::uint32_t>(
                (static_cast<std::uint16_t>(bytes[data + 1U]) << 8U) | bytes[data + 2U]);
            result.width = static_cast<std::uint32_t>(
                (static_cast<std::uint16_t>(bytes[data + 3U]) << 8U) | bytes[data + 4U]);
            result.components = bytes[data + 5U];
            if (result.components != 3U || segment_size < 8U + result.components * 3U) {
                return false;
            }
            result.chroma_subsampling = bytes[data + 7U];
            return result.width != 0U && result.height != 0U;
        }
        index += segment_size;
    }
    return false;
}

[[nodiscard]] WicJpegExportStatus verify_jpeg_readback(
    IWICImagingFactory* const factory,
    const std::filesystem::path& path,
    const Srgb16Image& expected,
    const std::vector<std::uint8_t>& expected_profile,
    const std::uint32_t dpi,
    WicJpegExportInfo& info,
    std::uint32_t& native_error_code) noexcept {
    ComPtr<IStream> stream{};
    HRESULT status = SHCreateStreamOnFileEx(
        path.c_str(),
        STGM_READ | STGM_SHARE_DENY_WRITE,
        FILE_ATTRIBUTE_NORMAL,
        FALSE,
        nullptr,
        &stream);
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicJpegExportStatus::decoder_initialization_failed;
    }
    ComPtr<IWICBitmapDecoder> decoder{};
    status = factory->CreateDecoderFromStream(
        stream.Get(),
        &GUID_VendorMicrosoft,
        WICDecodeMetadataCacheOnLoad,
        &decoder);
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicJpegExportStatus::decoder_initialization_failed;
    }
    ComPtr<IWICBitmapDecoderInfo> decoder_info{};
    CLSID decoder_class{};
    status = decoder->GetDecoderInfo(&decoder_info);
    if (SUCCEEDED(status)) {
        status = decoder_info->GetCLSID(&decoder_class);
    }
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicJpegExportStatus::decoder_initialization_failed;
    }
    if (IsEqualGUID(decoder_class, CLSID_WICJpegDecoder) == FALSE) {
        return WicJpegExportStatus::unexpected_decoder;
    }
    UINT frame_count = 0U;
    status = decoder->GetFrameCount(&frame_count);
    ComPtr<IWICBitmapFrameDecode> frame{};
    if (SUCCEEDED(status) && frame_count == 1U) {
        status = decoder->GetFrame(0U, &frame);
    }
    UINT width = 0U;
    UINT height = 0U;
    if (SUCCEEDED(status)) {
        status = frame->GetSize(&width, &height);
    }
    if (FAILED(status) || width != expected.width || height != expected.height) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicJpegExportStatus::readback_failed;
    }

    UINT context_count = 0U;
    status = frame->GetColorContexts(0U, nullptr, &context_count);
    ComPtr<IWICColorContext> context{};
    IWICColorContext* raw_context = nullptr;
    UINT actual_context_count = 0U;
    if (SUCCEEDED(status) && context_count == 1U) {
        status = factory->CreateColorContext(&context);
        raw_context = context.Get();
    }
    if (SUCCEEDED(status)) {
        status = frame->GetColorContexts(1U, &raw_context, &actual_context_count);
    }
    WICColorContextType context_type = WICColorContextUninitialized;
    UINT profile_size = 0U;
    if (SUCCEEDED(status)) {
        status = context->GetType(&context_type);
    }
    if (SUCCEEDED(status)) {
        status = context->GetProfileBytes(0U, nullptr, &profile_size);
    }
    if (FAILED(status) || actual_context_count != 1U ||
        context_type != WICColorContextProfile || profile_size != expected_profile.size()) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicJpegExportStatus::profile_verification_failed;
    }
    std::vector<std::uint8_t> actual_profile(profile_size);
    UINT actual_profile_size = 0U;
    status = context->GetProfileBytes(
        profile_size,
        actual_profile.data(),
        &actual_profile_size);
    if (FAILED(status) || actual_profile_size != profile_size ||
        actual_profile != expected_profile) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicJpegExportStatus::profile_verification_failed;
    }
    info.profile_verified = true;

    if (dpi != 0U) {
        double horizontal = 0.0;
        double vertical = 0.0;
        status = frame->GetResolution(&horizontal, &vertical);
        if (FAILED(status) || std::abs(horizontal - static_cast<double>(dpi)) > 0.05 ||
            std::abs(vertical - static_cast<double>(dpi)) > 0.05) {
            native_error_code = static_cast<std::uint32_t>(status);
            return WicJpegExportStatus::resolution_verification_failed;
        }
        info.resolution_verified = true;
    }
    return WicJpegExportStatus::ok;
}

}  // namespace

WicJpegExportResult export_working_to_srgb8_jpeg(
    const negaflow::imaging::WorkingImage& working,
    const std::filesystem::path& destination,
    const float quality,
    const std::uint32_t dpi,
    const WicJpegExportLimits& limits) noexcept {
    WicJpegExportResult result{};
    result.info.quality = quality;
    result.info.dpi = dpi;
    if (!std::isfinite(quality) || quality < 0.0F || quality > 1.0F) {
        result.status = WicJpegExportStatus::invalid_quality;
        return result;
    }
    const std::uint8_t expected_subsampling_option = quality >= 0.95F
        ? static_cast<std::uint8_t>(WICJpegYCrCbSubsampling444)
        : static_cast<std::uint8_t>(WICJpegYCrCbSubsampling420);
    const std::uint8_t expected_sampling_factor = quality >= 0.95F ? 0x11U : 0x22U;
    result.info.chroma_subsampling = expected_sampling_factor;
    try {
        WorkingToSrgb16Result converted =
            convert_working_to_srgb16(working, limits.conversion);
        result.conversion_status = converted.status;
        result.info.width = working.width;
        result.info.height = working.height;
        result.info.encoded_pixel_bytes = converted.info.encoded_pixel_bytes;
        result.info.clipped_color_components = converted.info.clipped_color_components;
        if (converted.status != WorkingToSrgb16Status::ok) {
            return result;
        }
        if (working.width > static_cast<std::uint32_t>(std::numeric_limits<INT>::max()) ||
            working.height > static_cast<std::uint32_t>(std::numeric_limits<INT>::max())) {
            result.conversion_status = WorkingToSrgb16Status::size_overflow;
            return result;
        }
        const detail::ComApartment apartment{};
        if (apartment.status() == RPC_E_CHANGED_MODE) {
            result.status = WicJpegExportStatus::com_apartment_mismatch;
            result.native_error_code = static_cast<std::uint32_t>(apartment.status());
            return result;
        }
        if (FAILED(apartment.status())) {
            result.status = WicJpegExportStatus::wic_unavailable;
            result.native_error_code = static_cast<std::uint32_t>(apartment.status());
            return result;
        }
        ComPtr<IWICImagingFactory2> factory{};
        if (!detail::create_wic_factory(factory, result.native_error_code)) {
            result.status = WicJpegExportStatus::wic_unavailable;
            return result;
        }
        ComPtr<IWICColorContext> color_context{};
        std::vector<std::uint8_t> profile_bytes{};
        switch (detail::load_standard_srgb_context(
            factory.Get(),
            limits.max_color_profile_bytes,
            color_context,
            profile_bytes,
            result.native_error_code)) {
            case detail::StandardSrgbStatus::ok:
                break;
            case detail::StandardSrgbStatus::unavailable:
                result.status = WicJpegExportStatus::destination_profile_unavailable;
                return result;
            case detail::StandardSrgbStatus::invalid:
                result.status = WicJpegExportStatus::destination_profile_invalid;
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
        result.status = encode_jpeg(
            factory.Get(),
            output->stream(),
            converted.image,
            color_context.Get(),
            quality,
            dpi,
            expected_subsampling_option,
            limits.metadata_policy,
            limits.metadata,
            result.native_error_code);
        if (result.status != WicJpegExportStatus::ok) {
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
        JpegStructure structure{};
        const bool valid_structure = inspect_jpeg_structure(
            output->staging_path(), limits.max_artifact_bytes, structure);
        result.info.chroma_subsampling = structure.chroma_subsampling;
        if (!valid_structure ||
            structure.width != converted.image.width || structure.height != converted.image.height ||
            structure.components != 3U ||
            structure.chroma_subsampling != expected_sampling_factor) {
            result.status = WicJpegExportStatus::structure_verification_failed;
            discard_staging(output.get(), result);
            return result;
        }
        std::error_code size_error{};
        result.info.artifact_bytes = std::filesystem::file_size(output->staging_path(), size_error);
        if (size_error || result.info.artifact_bytes == 0U) {
            result.status = WicJpegExportStatus::structure_verification_failed;
            discard_staging(output.get(), result);
            return result;
        }
        result.info.structure_verified = true;
        result.status = verify_jpeg_readback(
            factory.Get(),
            output->staging_path(),
            converted.image,
            profile_bytes,
            dpi,
            result.info,
            result.native_error_code);
        if (result.status != WicJpegExportStatus::ok) {
            discard_staging(output.get(), result);
            return result;
        }
        const detail::AtomicOutputStatus publish_status = output->publish(
            result.info.artifact_bytes,
            result.native_error_code);
        result.info.published = publish_status == detail::AtomicOutputStatus::ok ||
                                publish_status ==
                                    detail::AtomicOutputStatus::published_file_invalid;
        result.status = map_atomic_status(publish_status);
        if (!result.info.published) {
            discard_staging(output.get(), result);
        }
        return result;
    } catch (const std::bad_alloc&) {
        result.status = WicJpegExportStatus::allocation_failed;
        return result;
    } catch (...) {
        result.status = WicJpegExportStatus::encode_failed;
        return result;
    }
}

const char* wic_jpeg_export_status_name(const WicJpegExportStatus status) noexcept {
    switch (status) {
        case WicJpegExportStatus::ok: return "ok";
        case WicJpegExportStatus::invalid_quality: return "invalid_quality";
        case WicJpegExportStatus::working_conversion_failed: return "working_conversion_failed";
        case WicJpegExportStatus::allocation_failed: return "allocation_failed";
        case WicJpegExportStatus::com_apartment_mismatch: return "com_apartment_mismatch";
        case WicJpegExportStatus::wic_unavailable: return "wic_unavailable";
        case WicJpegExportStatus::destination_profile_unavailable: return "destination_profile_unavailable";
        case WicJpegExportStatus::destination_profile_invalid: return "destination_profile_invalid";
        case WicJpegExportStatus::destination_exists: return "destination_exists";
        case WicJpegExportStatus::staging_create_failed: return "staging_create_failed";
        case WicJpegExportStatus::encoder_initialization_failed: return "encoder_initialization_failed";
        case WicJpegExportStatus::unexpected_encoder: return "unexpected_encoder";
        case WicJpegExportStatus::pixel_format_coerced: return "pixel_format_coerced";
        case WicJpegExportStatus::resolution_configuration_failed: return "resolution_configuration_failed";
        case WicJpegExportStatus::encode_failed: return "encode_failed";
        case WicJpegExportStatus::flush_failed: return "flush_failed";
        case WicJpegExportStatus::structure_verification_failed: return "structure_verification_failed";
        case WicJpegExportStatus::decoder_initialization_failed: return "decoder_initialization_failed";
        case WicJpegExportStatus::unexpected_decoder: return "unexpected_decoder";
        case WicJpegExportStatus::readback_failed: return "readback_failed";
        case WicJpegExportStatus::profile_verification_failed: return "profile_verification_failed";
        case WicJpegExportStatus::resolution_verification_failed: return "resolution_verification_failed";
        case WicJpegExportStatus::publish_failed: return "publish_failed";
        case WicJpegExportStatus::published_file_invalid: return "published_file_invalid";
    }
    return "unknown";
}

}  // namespace negaflow::output
