#include "negaflow/output/wic_png_export.h"

#include "atomic_output_file.h"
#include "png_structure_reader.h"

#include "negaflow/color/icc_profile.h"

#include <Windows.h>
#include <Shlwapi.h>
#include <icm.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <new>
#include <vector>

namespace negaflow::output {
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

    [[nodiscard]] HRESULT status() const noexcept { return status_; }

private:
    HRESULT status_;
};

[[nodiscard]] bool create_wic_factory(
    ComPtr<IWICImagingFactory2>& factory,
    std::uint32_t& native_error_code) noexcept {
    const HRESULT status = CoCreateInstance(
        CLSID_WICImagingFactory2,
        nullptr,
        CLSCTX_INPROC_SERVER,
        IID_PPV_ARGS(&factory));
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return false;
    }
    return true;
}

[[nodiscard]] WicPngExportStatus load_standard_srgb_context(
    IWICImagingFactory* const factory,
    const WicPngExportLimits& limits,
    ComPtr<IWICColorContext>& context,
    std::vector<std::uint8_t>& profile_bytes,
    std::uint32_t& native_error_code) {
    DWORD path_bytes = 0U;
    SetLastError(ERROR_SUCCESS);
    const BOOL size_status =
        GetStandardColorSpaceProfileW(nullptr, LCS_sRGB, nullptr, &path_bytes);
    const DWORD size_error = GetLastError();
    if ((size_status == FALSE && size_error != ERROR_INSUFFICIENT_BUFFER) ||
        path_bytes < sizeof(wchar_t) || path_bytes > 32U * 1024U) {
        native_error_code = static_cast<std::uint32_t>(size_error);
        return WicPngExportStatus::destination_profile_unavailable;
    }
    std::vector<wchar_t> path(
        (static_cast<std::size_t>(path_bytes) + sizeof(wchar_t) - 1U) /
        sizeof(wchar_t));
    if (GetStandardColorSpaceProfileW(nullptr, LCS_sRGB, path.data(), &path_bytes) == FALSE) {
        native_error_code = static_cast<std::uint32_t>(GetLastError());
        return WicPngExportStatus::destination_profile_unavailable;
    }

    HRESULT status = factory->CreateColorContext(&context);
    if (SUCCEEDED(status)) {
        status = context->InitializeFromFilename(path.data());
    }
    UINT profile_size = 0U;
    if (SUCCEEDED(status)) {
        status = context->GetProfileBytes(0U, nullptr, &profile_size);
    }
    if (FAILED(status) || profile_size == 0U ||
        profile_size > limits.max_color_profile_bytes) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicPngExportStatus::destination_profile_unavailable;
    }
    profile_bytes.resize(profile_size);
    UINT actual_profile_size = 0U;
    status = context->GetProfileBytes(
        profile_size,
        profile_bytes.data(),
        &actual_profile_size);
    if (FAILED(status) || actual_profile_size != profile_size) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicPngExportStatus::destination_profile_unavailable;
    }
    const negaflow::color::IccProfileValidationResult validation =
        negaflow::color::validate_icc_profile(profile_bytes);
    if (validation.status != negaflow::color::IccProfileStatus::ok ||
        validation.info.data_color_space != 0x52474220U) {
        return WicPngExportStatus::destination_profile_invalid;
    }
    return WicPngExportStatus::ok;
}

[[nodiscard]] WicPngExportStatus encode_png(
    IWICImagingFactory* const factory,
    IStream* const stream,
    const Srgb16Image& image,
    IWICColorContext* const color_context,
    std::uint32_t& native_error_code) noexcept {
    ComPtr<IWICBitmapEncoder> encoder{};
    HRESULT status = factory->CreateEncoder(
        GUID_ContainerFormatPng,
        &GUID_VendorMicrosoft,
        &encoder);
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicPngExportStatus::encoder_initialization_failed;
    }
    ComPtr<IWICBitmapEncoderInfo> encoder_info{};
    CLSID encoder_class{};
    status = encoder->GetEncoderInfo(&encoder_info);
    if (SUCCEEDED(status)) {
        status = encoder_info->GetCLSID(&encoder_class);
    }
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicPngExportStatus::encoder_initialization_failed;
    }
    if (IsEqualGUID(encoder_class, CLSID_WICPngEncoder) == FALSE) {
        return WicPngExportStatus::unexpected_encoder;
    }

    status = encoder->Initialize(stream, WICBitmapEncoderNoCache);
    ComPtr<IWICBitmapFrameEncode> frame{};
    ComPtr<IPropertyBag2> options{};
    if (SUCCEEDED(status)) {
        status = encoder->CreateNewFrame(&frame, &options);
    }
    if (SUCCEEDED(status)) {
        status = frame->Initialize(options.Get());
    }
    if (SUCCEEDED(status)) {
        status = frame->SetSize(image.width, image.height);
    }
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicPngExportStatus::encoder_initialization_failed;
    }

    WICPixelFormatGUID pixel_format = GUID_WICPixelFormat48bppRGB;
    status = frame->SetPixelFormat(&pixel_format);
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicPngExportStatus::encoder_initialization_failed;
    }
    if (IsEqualGUID(pixel_format, GUID_WICPixelFormat48bppRGB) == FALSE) {
        return WicPngExportStatus::pixel_format_coerced;
    }
    IWICColorContext* contexts[]{color_context};
    status = frame->SetColorContexts(1U, contexts);
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicPngExportStatus::encode_failed;
    }

    const std::uint64_t max_rows_per_write =
        std::numeric_limits<UINT>::max() / image.stride_bytes;
    if (max_rows_per_write == 0U) {
        return WicPngExportStatus::encode_failed;
    }
    std::uint32_t completed_rows = 0U;
    while (completed_rows < image.height) {
        const UINT row_count = static_cast<UINT>(std::min<std::uint64_t>(
            image.height - completed_rows,
            max_rows_per_write));
        const UINT buffer_bytes = row_count * image.stride_bytes;
        const std::size_t sample_offset =
            static_cast<std::size_t>(completed_rows) * image.width * 3U;
        status = frame->WritePixels(
            row_count,
            image.stride_bytes,
            buffer_bytes,
            reinterpret_cast<BYTE*>(
                const_cast<std::uint16_t*>(image.samples.data() + sample_offset)));
        if (FAILED(status)) {
            native_error_code = static_cast<std::uint32_t>(status);
            return WicPngExportStatus::encode_failed;
        }
        completed_rows += row_count;
    }
    status = frame->Commit();
    if (SUCCEEDED(status)) {
        status = encoder->Commit();
    }
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicPngExportStatus::encode_failed;
    }
    return WicPngExportStatus::ok;
}

[[nodiscard]] WicPngExportStatus verify_profile(
    IWICImagingFactory* const factory,
    IWICBitmapFrameDecode* const frame,
    const std::vector<std::uint8_t>& expected_profile,
    std::uint32_t& native_error_code) {
    UINT context_count = 0U;
    HRESULT status = frame->GetColorContexts(0U, nullptr, &context_count);
    if (FAILED(status) || context_count != 1U) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicPngExportStatus::profile_verification_failed;
    }
    ComPtr<IWICColorContext> context{};
    status = factory->CreateColorContext(&context);
    IWICColorContext* raw_context = context.Get();
    UINT actual_context_count = 0U;
    if (SUCCEEDED(status)) {
        status = frame->GetColorContexts(1U, &raw_context, &actual_context_count);
    }
    WICColorContextType context_type = WICColorContextUninitialized;
    if (SUCCEEDED(status)) {
        status = context->GetType(&context_type);
    }
    UINT profile_size = 0U;
    if (SUCCEEDED(status)) {
        status = context->GetProfileBytes(0U, nullptr, &profile_size);
    }
    if (FAILED(status) || actual_context_count != 1U ||
        context_type != WICColorContextProfile ||
        profile_size != expected_profile.size()) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicPngExportStatus::profile_verification_failed;
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
        return WicPngExportStatus::profile_verification_failed;
    }
    return WicPngExportStatus::ok;
}

[[nodiscard]] WicPngExportStatus verify_png_readback(
    IWICImagingFactory* const factory,
    const std::filesystem::path& path,
    const Srgb16Image& expected,
    const std::vector<std::uint8_t>& expected_profile,
    const WicPngExportLimits& limits,
    std::uint32_t& native_error_code) {
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
        return WicPngExportStatus::decoder_initialization_failed;
    }
    ComPtr<IWICBitmapDecoder> decoder{};
    status = factory->CreateDecoderFromStream(
        stream.Get(),
        &GUID_VendorMicrosoft,
        WICDecodeMetadataCacheOnLoad,
        &decoder);
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicPngExportStatus::decoder_initialization_failed;
    }
    ComPtr<IWICBitmapDecoderInfo> decoder_info{};
    CLSID decoder_class{};
    status = decoder->GetDecoderInfo(&decoder_info);
    if (SUCCEEDED(status)) {
        status = decoder_info->GetCLSID(&decoder_class);
    }
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicPngExportStatus::decoder_initialization_failed;
    }
    if (IsEqualGUID(decoder_class, CLSID_WICPngDecoder) == FALSE) {
        return WicPngExportStatus::unexpected_decoder;
    }

    UINT frame_count = 0U;
    status = decoder->GetFrameCount(&frame_count);
    if (FAILED(status) || frame_count != 1U) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicPngExportStatus::readback_failed;
    }
    ComPtr<IWICBitmapFrameDecode> frame{};
    status = decoder->GetFrame(0U, &frame);
    UINT width = 0U;
    UINT height = 0U;
    WICPixelFormatGUID format{};
    if (SUCCEEDED(status)) {
        status = frame->GetSize(&width, &height);
    }
    if (SUCCEEDED(status)) {
        status = frame->GetPixelFormat(&format);
    }
    if (FAILED(status) || width != expected.width || height != expected.height ||
        IsEqualGUID(format, GUID_WICPixelFormat48bppRGB) == FALSE) {
        native_error_code = static_cast<std::uint32_t>(status);
        return WicPngExportStatus::readback_failed;
    }

    if (limits.readback_buffer_bytes < expected.stride_bytes) {
        return WicPngExportStatus::readback_failed;
    }
    const std::uint32_t rows_per_copy =
        limits.readback_buffer_bytes / expected.stride_bytes;
    const std::uint32_t allocated_rows = std::min(rows_per_copy, expected.height);
    const std::uint64_t buffer_bytes_64 =
        static_cast<std::uint64_t>(allocated_rows) * expected.stride_bytes;
    if (buffer_bytes_64 > std::numeric_limits<UINT>::max()) {
        return WicPngExportStatus::readback_failed;
    }
    std::vector<std::uint16_t> buffer(
        static_cast<std::size_t>(buffer_bytes_64 / sizeof(std::uint16_t)));
    for (std::uint32_t row = 0U; row < expected.height;) {
        const std::uint32_t row_count = std::min(rows_per_copy, expected.height - row);
        const UINT buffer_bytes = row_count * expected.stride_bytes;
        WICRect rectangle{
            0,
            static_cast<INT>(row),
            static_cast<INT>(expected.width),
            static_cast<INT>(row_count),
        };
        status = frame->CopyPixels(
            &rectangle,
            expected.stride_bytes,
            buffer_bytes,
            reinterpret_cast<BYTE*>(buffer.data()));
        if (FAILED(status)) {
            native_error_code = static_cast<std::uint32_t>(status);
            return WicPngExportStatus::readback_failed;
        }
        const std::size_t expected_offset =
            static_cast<std::size_t>(row) * expected.width * 3U;
        const std::size_t sample_count =
            static_cast<std::size_t>(row_count) * expected.width * 3U;
        if (!std::equal(
                buffer.begin(),
                buffer.begin() + static_cast<std::ptrdiff_t>(sample_count),
                expected.samples.begin() + static_cast<std::ptrdiff_t>(expected_offset))) {
            return WicPngExportStatus::pixel_verification_failed;
        }
        row += row_count;
    }
    return verify_profile(factory, frame.Get(), expected_profile, native_error_code);
}

[[nodiscard]] WicPngExportStatus map_atomic_status(
    const detail::AtomicOutputStatus status) noexcept {
    switch (status) {
        case detail::AtomicOutputStatus::ok:
            return WicPngExportStatus::ok;
        case detail::AtomicOutputStatus::destination_exists:
            return WicPngExportStatus::destination_exists;
        case detail::AtomicOutputStatus::flush_failed:
            return WicPngExportStatus::flush_failed;
        case detail::AtomicOutputStatus::published_file_invalid:
            return WicPngExportStatus::published_file_invalid;
        case detail::AtomicOutputStatus::publish_failed:
            return WicPngExportStatus::publish_failed;
        case detail::AtomicOutputStatus::allocation_failed:
            return WicPngExportStatus::allocation_failed;
        case detail::AtomicOutputStatus::invalid_path:
        case detail::AtomicOutputStatus::destination_query_failed:
        case detail::AtomicOutputStatus::parent_unavailable:
        case detail::AtomicOutputStatus::staging_create_failed:
            return WicPngExportStatus::staging_create_failed;
    }
    return WicPngExportStatus::staging_create_failed;
}

void discard_staging(
    detail::AtomicOutputFile* const output,
    WicPngExportResult& result) noexcept {
    if (output != nullptr) {
        output->discard(result.cleanup_error_code);
    }
}

}  // namespace

WicPngExportResult export_working_to_srgb16_png(
    const negaflow::imaging::WorkingImage& working,
    const std::filesystem::path& destination,
    const WicPngExportLimits& limits) noexcept {
    WicPngExportResult result{};
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

        const ComApartment apartment{};
        if (apartment.status() == RPC_E_CHANGED_MODE) {
            result.status = WicPngExportStatus::com_apartment_mismatch;
            result.native_error_code = static_cast<std::uint32_t>(apartment.status());
            return result;
        }
        if (FAILED(apartment.status())) {
            result.status = WicPngExportStatus::wic_unavailable;
            result.native_error_code = static_cast<std::uint32_t>(apartment.status());
            return result;
        }
        ComPtr<IWICImagingFactory2> factory{};
        if (!create_wic_factory(factory, result.native_error_code)) {
            result.status = WicPngExportStatus::wic_unavailable;
            return result;
        }

        ComPtr<IWICColorContext> color_context{};
        std::vector<std::uint8_t> profile_bytes{};
        result.status = load_standard_srgb_context(
            factory.Get(),
            limits,
            color_context,
            profile_bytes,
            result.native_error_code);
        if (result.status != WicPngExportStatus::ok) {
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

        result.status = encode_png(
            factory.Get(),
            output->stream(),
            converted.image,
            color_context.Get(),
            result.native_error_code);
        if (result.status != WicPngExportStatus::ok) {
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

        detail::PngStructureInfo structure{};
        const detail::PngStructureStatus structure_status = detail::inspect_png_structure(
            output->staging_path(),
            limits.max_artifact_bytes,
            structure,
            result.native_error_code);
        result.info.artifact_bytes = structure.file_bytes;
        result.info.image_data_chunks = structure.image_data_chunks;
        if (structure_status != detail::PngStructureStatus::ok ||
            structure.width != converted.image.width ||
            structure.height != converted.image.height || structure.bit_depth != 16U ||
            structure.color_type != 2U) {
            result.status = WicPngExportStatus::structure_verification_failed;
            discard_staging(output.get(), result);
            return result;
        }
        result.info.structure_verified = true;

        result.status = verify_png_readback(
            factory.Get(),
            output->staging_path(),
            converted.image,
            profile_bytes,
            limits,
            result.native_error_code);
        if (result.status != WicPngExportStatus::ok) {
            discard_staging(output.get(), result);
            return result;
        }
        result.info.pixels_verified = true;
        result.info.profile_verified = true;

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
        result.status = WicPngExportStatus::allocation_failed;
        return result;
    } catch (...) {
        result.status = WicPngExportStatus::encode_failed;
        return result;
    }
}

const char* wic_png_export_status_name(const WicPngExportStatus status) noexcept {
    switch (status) {
        case WicPngExportStatus::ok:
            return "ok";
        case WicPngExportStatus::working_conversion_failed:
            return "working_conversion_failed";
        case WicPngExportStatus::allocation_failed:
            return "allocation_failed";
        case WicPngExportStatus::com_apartment_mismatch:
            return "com_apartment_mismatch";
        case WicPngExportStatus::wic_unavailable:
            return "wic_unavailable";
        case WicPngExportStatus::destination_profile_unavailable:
            return "destination_profile_unavailable";
        case WicPngExportStatus::destination_profile_invalid:
            return "destination_profile_invalid";
        case WicPngExportStatus::destination_exists:
            return "destination_exists";
        case WicPngExportStatus::staging_create_failed:
            return "staging_create_failed";
        case WicPngExportStatus::encoder_initialization_failed:
            return "encoder_initialization_failed";
        case WicPngExportStatus::unexpected_encoder:
            return "unexpected_encoder";
        case WicPngExportStatus::pixel_format_coerced:
            return "pixel_format_coerced";
        case WicPngExportStatus::encode_failed:
            return "encode_failed";
        case WicPngExportStatus::flush_failed:
            return "flush_failed";
        case WicPngExportStatus::structure_verification_failed:
            return "structure_verification_failed";
        case WicPngExportStatus::decoder_initialization_failed:
            return "decoder_initialization_failed";
        case WicPngExportStatus::unexpected_decoder:
            return "unexpected_decoder";
        case WicPngExportStatus::readback_failed:
            return "readback_failed";
        case WicPngExportStatus::pixel_verification_failed:
            return "pixel_verification_failed";
        case WicPngExportStatus::profile_verification_failed:
            return "profile_verification_failed";
        case WicPngExportStatus::publish_failed:
            return "publish_failed";
        case WicPngExportStatus::published_file_invalid:
            return "published_file_invalid";
    }
    return "unknown";
}

}  // namespace negaflow::output
