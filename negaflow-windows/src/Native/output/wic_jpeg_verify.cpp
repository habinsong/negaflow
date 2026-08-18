#include "wic_jpeg_verify.h"

#include <Shlwapi.h>
#include <wrl/client.h>

#include <algorithm>
#include <cmath>
#include <fstream>
#include <limits>
#include <new>

namespace negaflow::output::wic_jpeg_detail {

using Microsoft::WRL::ComPtr;

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

}  // namespace negaflow::output::wic_jpeg_detail
