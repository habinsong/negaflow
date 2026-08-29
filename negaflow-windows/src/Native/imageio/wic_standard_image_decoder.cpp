#include "negaflow/imageio/wic_standard_image_decoder.h"

#include "negaflow/imageio/libraw_image_decoder.h"

#include "wic_orientation.h"

#include <Windows.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <cstddef>
#include <cstdint>
#include <limits>
#include <new>
#include <string>
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

    [[nodiscard]] HRESULT status() const noexcept { return status_; }

private:
    HRESULT status_;
};

void discard_samples(WicStandardImageDecodeResult& result) noexcept {
    std::vector<std::uint16_t>{}.swap(result.image.samples);
}

[[nodiscard]] bool supported_container(const GUID& format) noexcept {
    return IsEqualGUID(format, GUID_ContainerFormatJpeg) != 0 ||
           IsEqualGUID(format, GUID_ContainerFormatPng) != 0 ||
           IsEqualGUID(format, GUID_ContainerFormatRaw) != 0;
}

[[nodiscard]] WicStandardImageDecodeStatus configure_raw_development(
    IWICImagingFactory* const factory,
    IWICBitmapFrameDecode* const frame) noexcept {
    ComPtr<IWICDevelopRaw> raw{};
    if (FAILED(frame->QueryInterface(IID_PPV_ARGS(&raw))) ||
        FAILED(raw->LoadParameterSet(WICAsShotParameterSet)) ||
        FAILED(raw->SetRenderMode(WICRawRenderModeBestQuality))) {
        return WicStandardImageDecodeStatus::raw_development_failed;
    }
    ComPtr<IWICColorContext> srgb{};
    if (FAILED(factory->CreateColorContext(&srgb)) ||
        FAILED(srgb->InitializeFromExifColorSpace(1U)) ||
        FAILED(raw->SetDestinationColorContext(srgb.Get()))) {
        return WicStandardImageDecodeStatus::raw_development_failed;
    }
    return WicStandardImageDecodeStatus::ok;
}

[[nodiscard]] std::uint16_t exif_orientation(
    IWICBitmapFrameDecode* const frame) noexcept {
    ComPtr<IWICMetadataQueryReader> reader{};
    if (FAILED(frame->GetMetadataQueryReader(&reader))) {
        return 1U;
    }
    PROPVARIANT value{};
    PropVariantInit(&value);
    const HRESULT status = reader->GetMetadataByName(
        L"/app1/ifd/{ushort=274}", &value);
    std::uint32_t orientation = 1U;
    if (SUCCEEDED(status)) {
        switch (value.vt) {
            case VT_UI2: orientation = value.uiVal; break;
            case VT_UI4: orientation = value.ulVal; break;
            case VT_I2: orientation = static_cast<std::uint16_t>(value.iVal); break;
            case VT_I4: orientation = static_cast<std::uint32_t>(value.lVal); break;
            default: break;
        }
    }
    PropVariantClear(&value);
    return orientation >= 1U && orientation <= 8U
        ? static_cast<std::uint16_t>(orientation)
        : 1U;
}

/// EXIF 하위 IFD 가 붙는 자리는 컨테이너마다 다릅니다. JPEG 은 APP1 안이고, TIFF 은
/// 최상위 IFD 안입니다. 태그만 읽으므로 둘 다 시도합니다 — 하나만 걸면 가져온 TIFF 의
/// 촬영 기록이 통째로 비어 보입니다.
constexpr const wchar_t* exif_query_roots[] = {
    L"/app1/ifd/exif/",
    L"/ifd/exif/",
};

/// WIC 은 EXIF RATIONAL 을 `VT_UI8` 하나로 돌려줍니다 — 하위 32비트가 분자, 상위 32비트가
/// 분모입니다. SRATIONAL 은 같은 자리 `VT_I8` 입니다. 이 규칙을 모르면 1/125 초가
/// 536870912125 같은 숫자로 읽힙니다.
[[nodiscard]] bool rational_to_double(const std::uint64_t packed, double& value) noexcept {
    const std::uint32_t numerator = static_cast<std::uint32_t>(packed & 0xFFFFFFFFULL);
    const std::uint32_t denominator = static_cast<std::uint32_t>(packed >> 32U);
    if (denominator == 0U) return false;
    value = static_cast<double>(numerator) / static_cast<double>(denominator);
    return true;
}

[[nodiscard]] bool signed_rational_to_double(const std::int64_t packed, double& value) noexcept {
    const std::int32_t numerator = static_cast<std::int32_t>(
        static_cast<std::uint32_t>(static_cast<std::uint64_t>(packed) & 0xFFFFFFFFULL));
    const std::int32_t denominator = static_cast<std::int32_t>(
        static_cast<std::uint32_t>(static_cast<std::uint64_t>(packed) >> 32U));
    if (denominator == 0) return false;
    value = static_cast<double>(numerator) / static_cast<double>(denominator);
    return true;
}

/// PROPVARIANT 하나를 실수로 접습니다. 벡터는 **첫 원소**만 씁니다 — macOS 도
/// `isoSpeedRatings.first` 로 첫 값만 보여 줍니다.
[[nodiscard]] bool propvariant_to_double(const PROPVARIANT& value, double& out) noexcept {
    switch (value.vt) {
        case VT_UI2: out = static_cast<double>(value.uiVal); return true;
        case VT_UI4: out = static_cast<double>(value.ulVal); return true;
        case VT_I2: out = static_cast<double>(value.iVal); return true;
        case VT_I4: out = static_cast<double>(value.lVal); return true;
        case VT_R4: out = static_cast<double>(value.fltVal); return true;
        case VT_R8: out = value.dblVal; return true;
        case VT_UI8: return rational_to_double(value.uhVal.QuadPart, out);
        case VT_I8: return signed_rational_to_double(value.hVal.QuadPart, out);
        case VT_VECTOR | VT_UI2:
            if (value.caui.cElems == 0U) return false;
            out = static_cast<double>(value.caui.pElems[0]);
            return true;
        case VT_VECTOR | VT_UI4:
            if (value.caul.cElems == 0U) return false;
            out = static_cast<double>(value.caul.pElems[0]);
            return true;
        case VT_VECTOR | VT_UI8:
            if (value.cauh.cElems == 0U) return false;
            return rational_to_double(value.cauh.pElems[0].QuadPart, out);
        case VT_VECTOR | VT_I8:
            if (value.cah.cElems == 0U) return false;
            return signed_rational_to_double(value.cah.pElems[0].QuadPart, out);
        default: return false;
    }
}

/// EXIF 태그 하나를 읽습니다. 값이 없거나 형이 낯설면 **없는 것으로 둡니다** — 지어내지
/// 않습니다.
[[nodiscard]] bool read_exif_double(
    IWICMetadataQueryReader* const reader,
    const wchar_t* const tag_suffix,
    double& out) noexcept {
    for (const wchar_t* const root : exif_query_roots) {
        std::wstring query{root};
        query.append(tag_suffix);
        PROPVARIANT value{};
        PropVariantInit(&value);
        const HRESULT status = reader->GetMetadataByName(query.c_str(), &value);
        const bool read = SUCCEEDED(status) && propvariant_to_double(value, out);
        PropVariantClear(&value);
        if (read) return true;
    }
    return false;
}

[[nodiscard]] bool positive_finite(const double value) noexcept {
    return value > 0.0 && value < 1.0e9 && value == value;
}

/// EXIF 촬영 태그 넷을 읽습니다. macOS `SourceMetadataReader+ImageProperties` 가 읽는
/// `kCGImagePropertyExifISOSpeedRatings` · `ExposureTime` · `FNumber` · `FocalLength` 와
/// 같은 태그 번호입니다.
[[nodiscard]] SourceShotMetadata read_shot_metadata(
    IWICBitmapFrameDecode* const frame) noexcept {
    SourceShotMetadata shot{};
    ComPtr<IWICMetadataQueryReader> reader{};
    if (FAILED(frame->GetMetadataQueryReader(&reader))) {
        return shot;
    }
    double value = 0.0;
    // ISOSpeedRatings(34855). 배열이면 첫 값입니다.
    if (read_exif_double(reader.Get(), L"{ushort=34855}", value) && positive_finite(value)) {
        shot.has_iso_speed = true;
        shot.iso_speed = static_cast<std::uint32_t>(value + 0.5);
    }
    // ExposureTime(33434), 초 단위 RATIONAL.
    if (read_exif_double(reader.Get(), L"{ushort=33434}", value) && positive_finite(value)) {
        shot.has_exposure_time = true;
        shot.exposure_time_seconds = value;
    }
    // FNumber(33437).
    if (read_exif_double(reader.Get(), L"{ushort=33437}", value) && positive_finite(value)) {
        shot.has_f_number = true;
        shot.f_number = value;
    }
    // FocalLength(37386), mm.
    if (read_exif_double(reader.Get(), L"{ushort=37386}", value) && positive_finite(value)) {
        shot.has_focal_length = true;
        shot.focal_length_mm = value;
    }
    return shot;
}

[[nodiscard]] WicStandardImageDecodeStatus extract_icc_profile(
    IWICImagingFactory* const factory,
    IWICBitmapFrameDecode* const frame,
    const WicStandardImageDecodeLimits& limits,
    WicStandardImageDecodeResult& result) {
    UINT count = 0U;
    HRESULT status = frame->GetColorContexts(0U, nullptr, &count);
    if (status == WINCODEC_ERR_UNSUPPORTEDOPERATION) {
        return WicStandardImageDecodeStatus::ok;
    }
    if (FAILED(status) || count > limits.max_color_contexts) {
        return WicStandardImageDecodeStatus::color_context_failed;
    }
    if (count == 0U) {
        return WicStandardImageDecodeStatus::ok;
    }

    std::vector<ComPtr<IWICColorContext>> contexts(count);
    std::vector<IWICColorContext*> raw_contexts(count, nullptr);
    for (UINT index = 0U; index < count; ++index) {
        if (FAILED(factory->CreateColorContext(&contexts[index]))) {
            return WicStandardImageDecodeStatus::color_context_failed;
        }
        raw_contexts[index] = contexts[index].Get();
    }
    UINT actual_count = 0U;
    if (FAILED(frame->GetColorContexts(count, raw_contexts.data(), &actual_count)) ||
        actual_count != count) {
        return WicStandardImageDecodeStatus::color_context_failed;
    }

    bool profile_found = false;
    for (const ComPtr<IWICColorContext>& context : contexts) {
        WICColorContextType type = WICColorContextUninitialized;
        if (FAILED(context->GetType(&type))) {
            return WicStandardImageDecodeStatus::color_context_failed;
        }
        if (type != WICColorContextProfile) {
            continue;
        }
        if (profile_found) {
            return WicStandardImageDecodeStatus::color_context_failed;
        }
        profile_found = true;
        UINT bytes = 0U;
        if (FAILED(context->GetProfileBytes(0U, nullptr, &bytes)) ||
            bytes == 0U || bytes > limits.icc.max_profile_bytes) {
            return WicStandardImageDecodeStatus::color_context_failed;
        }
        result.image.icc_profile.resize(bytes);
        UINT actual_bytes = 0U;
        if (FAILED(context->GetProfileBytes(
                bytes,
                result.image.icc_profile.data(),
                &actual_bytes)) ||
            actual_bytes != bytes) {
            return WicStandardImageDecodeStatus::color_context_failed;
        }
    }
    if (!profile_found) {
        return WicStandardImageDecodeStatus::ok;
    }

    const negaflow::color::IccProfileValidationResult validation =
        negaflow::color::validate_icc_profile(result.image.icc_profile, limits.icc);
    result.icc_status = validation.status;
    result.info.icc = validation.info;
    return validation.status == negaflow::color::IccProfileStatus::ok
        ? WicStandardImageDecodeStatus::ok
        : WicStandardImageDecodeStatus::invalid_icc_profile;
}

}  // namespace

namespace {

/// WIC 가 이 파일을 열 codec 자체를 못 찾았는지 봅니다.
///
/// Windows 에 항상 있는 WIC codec 은 BMP·GIF·ICO·JPEG·JPEG XR·PNG·TIFF·HD Photo·DDS
/// 아홉 개뿐이고 **카메라 RAW 은 없습니다.** RAW 은 Microsoft Store 의 별도 패키지라
/// 선탑재가 보장되지 않으므로, 여기 걸린 파일은 "깨졌다" 가 아니라 "읽을 codec 이
/// 없다" 일 수 있습니다. 그때 함께 배포한 LibRaw 로 한 번 더 시도합니다.
[[nodiscard]] bool missing_codec(const WicStandardImageDecodeStatus status) noexcept {
    return status == WicStandardImageDecodeStatus::decoder_initialization_failed ||
        status == WicStandardImageDecodeStatus::unsupported_container ||
        status == WicStandardImageDecodeStatus::raw_development_failed;
}

/// LibRaw 가 돌려준 rgba16 을 프리뷰 크기로 줄입니다.
///
/// WIC 경로는 `IWICBitmapScaler` 가 디코드하면서 줄이지만, LibRaw 는 이미 다 만들어 놓고
/// 돌려줍니다. 그것을 그대로 두면 이어지는 working 변환과 파이프라인이 원본 화소 수만큼
/// 돌고, working 이미지 하나가 수백 MB 가 됩니다(실측: 6000x4000 한 장이 384 MB). 같은
/// 스케일러로 줄여 그 뒤 단계 전부를 프리뷰 크기로 만듭니다.
[[nodiscard]] bool shrink_decoded_rgba16(
    DecodedImage& image,
    const WicStandardImageDecodeControl& control) noexcept {
    if (control.max_output_width == 0U || control.max_output_height == 0U ||
        image.layout != DecodedPixelLayout::rgba16 || image.width == 0U || image.height == 0U ||
        (image.width <= control.max_output_width && image.height <= control.max_output_height)) {
        return false;
    }
    UINT fitted_width = image.width;
    UINT fitted_height = image.height;
    if (fitted_width > control.max_output_width) {
        fitted_width = control.max_output_width;
        fitted_height = static_cast<UINT>(
            (static_cast<std::uint64_t>(image.height) * fitted_width) / image.width);
        if (fitted_height == 0U) fitted_height = 1U;
    }
    if (fitted_height > control.max_output_height) {
        fitted_height = control.max_output_height;
        fitted_width = static_cast<UINT>(
            (static_cast<std::uint64_t>(image.width) * fitted_height) / image.height);
        if (fitted_width == 0U) fitted_width = 1U;
    }
    try {
        const ComApartment apartment{};
        if (FAILED(apartment.status())) {
            return false;
        }
        ComPtr<IWICImagingFactory> factory{};
        if (FAILED(CoCreateInstance(
                CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory)))) {
            return false;
        }
        const UINT source_stride = image.stride_bytes != 0U
            ? image.stride_bytes
            : static_cast<UINT>(image.width) * 8U;
        ComPtr<IWICBitmap> source{};
        if (FAILED(factory->CreateBitmapFromMemory(
                image.width,
                image.height,
                GUID_WICPixelFormat64bppRGBA,
                source_stride,
                static_cast<UINT>(image.samples.size() * sizeof(std::uint16_t)),
                reinterpret_cast<BYTE*>(image.samples.data()),
                &source))) {
            return false;
        }
        ComPtr<IWICBitmapScaler> scaler{};
        if (FAILED(factory->CreateBitmapScaler(&scaler)) ||
            FAILED(scaler->Initialize(
                source.Get(),
                fitted_width,
                fitted_height,
                WICBitmapInterpolationModeHighQualityCubic))) {
            return false;
        }
        const std::uint64_t stride = static_cast<std::uint64_t>(fitted_width) * 8ULL;
        const std::uint64_t bytes = stride * fitted_height;
        if (stride > std::numeric_limits<UINT>::max() || bytes > std::numeric_limits<UINT>::max()) {
            return false;
        }
        std::vector<std::uint16_t> scaled(static_cast<std::size_t>(bytes / sizeof(std::uint16_t)));
        if (FAILED(scaler->CopyPixels(
                nullptr,
                static_cast<UINT>(stride),
                static_cast<UINT>(bytes),
                reinterpret_cast<BYTE*>(scaled.data())))) {
            return false;
        }
        image.samples = std::move(scaled);
        image.width = fitted_width;
        image.height = fitted_height;
        image.stride_bytes = static_cast<std::uint32_t>(stride);
        return true;
    } catch (...) {
        return false;
    }
}

}  // namespace

StandardImageMetadataResult probe_standard_image_metadata(
    const std::filesystem::path& path) noexcept {
    StandardImageMetadataResult result{};
    try {
        if (path.empty()) {
            result.status = StandardImageMetadataStatus::invalid_argument;
            return result;
        }
        const ComApartment apartment{};
        if (apartment.status() == RPC_E_CHANGED_MODE) {
            result.status = StandardImageMetadataStatus::com_apartment_mismatch;
            return result;
        }
        if (SUCCEEDED(apartment.status())) {
            ComPtr<IWICImagingFactory> factory{};
            ComPtr<IWICBitmapDecoder> decoder{};
            if (SUCCEEDED(CoCreateInstance(
                    CLSID_WICImagingFactory,
                    nullptr,
                    CLSCTX_INPROC_SERVER,
                    IID_PPV_ARGS(&factory))) &&
                SUCCEEDED(factory->CreateDecoderFromFilename(
                    path.c_str(),
                    nullptr,
                    GENERIC_READ,
                    WICDecodeMetadataCacheOnDemand,
                    &decoder))) {
                GUID format{};
                UINT frames = 0U;
                ComPtr<IWICBitmapFrameDecode> frame{};
                UINT width = 0U;
                UINT height = 0U;
                if (SUCCEEDED(decoder->GetContainerFormat(&format)) &&
                    supported_container(format) &&
                    SUCCEEDED(decoder->GetFrameCount(&frames)) && frames == 1U &&
                    SUCCEEDED(decoder->GetFrame(0U, &frame)) &&
                    SUCCEEDED(frame->GetSize(&width, &height)) && width != 0U && height != 0U) {
                    result.status = StandardImageMetadataStatus::ok;
                    result.metadata.pixel_width = width;
                    result.metadata.pixel_height = height;
                    result.metadata.exif_orientation = exif_orientation(frame.Get());
                    return result;
                }
            }
        }
        // WIC 가 못 열었습니다. 카메라 RAW 이면 함께 배포한 `libraw.dll` 이 헤더를 읽습니다 —
        // 디코드 경로와 같은 대체 관계입니다.
        const LibRawMetadataResult raw = probe_raw_metadata_with_libraw(path);
        if (raw.status == LibRawDecodeStatus::ok) {
            result.status = StandardImageMetadataStatus::ok;
            result.metadata.pixel_width = raw.pixel_width;
            result.metadata.pixel_height = raw.pixel_height;
            result.metadata.libraw_fallback_used = true;
            return result;
        }
        result.status = raw.status == LibRawDecodeStatus::unavailable
            ? StandardImageMetadataStatus::unreadable
            : StandardImageMetadataStatus::unsupported;
        return result;
    } catch (...) {
        result.status = StandardImageMetadataStatus::unreadable;
        return result;
    }
}

SourceShotMetadataResult probe_source_shot_metadata(
    const std::filesystem::path& path) noexcept {
    SourceShotMetadataResult result{};
    try {
        if (path.empty()) {
            result.status = StandardImageMetadataStatus::invalid_argument;
            return result;
        }
        const ComApartment apartment{};
        if (apartment.status() == RPC_E_CHANGED_MODE) {
            result.status = StandardImageMetadataStatus::com_apartment_mismatch;
            return result;
        }
        if (SUCCEEDED(apartment.status())) {
            ComPtr<IWICImagingFactory> factory{};
            ComPtr<IWICBitmapDecoder> decoder{};
            ComPtr<IWICBitmapFrameDecode> frame{};
            if (SUCCEEDED(CoCreateInstance(
                    CLSID_WICImagingFactory,
                    nullptr,
                    CLSCTX_INPROC_SERVER,
                    IID_PPV_ARGS(&factory))) &&
                SUCCEEDED(factory->CreateDecoderFromFilename(
                    path.c_str(),
                    nullptr,
                    GENERIC_READ,
                    WICDecodeMetadataCacheOnDemand,
                    &decoder)) &&
                SUCCEEDED(decoder->GetFrame(0U, &frame))) {
                result.status = StandardImageMetadataStatus::ok;
                result.shot = read_shot_metadata(frame.Get());
                // WIC 이 열긴 했는데 촬영 태그가 하나도 없을 수 있습니다. 카메라 RAW 이면
                // `libraw.dll` 이 같은 값을 들고 있으므로 한 번 더 물어봅니다 — 열었다는
                // 이유만으로 빈 값을 확정하면 RAW codec 이 깔린 기계에서만 값이 비어
                // 보입니다.
                if (!result.shot.empty()) {
                    return result;
                }
            }
        }
        const LibRawShotResult raw = probe_raw_shot_with_libraw(path);
        if (raw.status == LibRawDecodeStatus::ok) {
            result.status = StandardImageMetadataStatus::ok;
            result.shot = raw.shot;
            result.libraw_fallback_used = true;
            return result;
        }
        if (result.status == StandardImageMetadataStatus::ok) {
            // WIC 은 열었습니다. 촬영 기록이 없는 파일일 뿐입니다.
            return result;
        }
        result.status = raw.status == LibRawDecodeStatus::unavailable
            ? StandardImageMetadataStatus::unreadable
            : StandardImageMetadataStatus::unsupported;
        return result;
    } catch (...) {
        result.status = StandardImageMetadataStatus::unreadable;
        return result;
    }
}

WicStandardImageDecodeResult decode_standard_image_with_wic(
    const std::filesystem::path& path,
    const WicStandardImageDecodeLimits& limits,
    const std::stop_token stop_token,
    const WicStandardImageDecodeControl& control) noexcept {
    WicStandardImageDecodeResult wic =
        decode_standard_image_with_wic_only(path, limits, stop_token, control);
    if (wic.status == WicStandardImageDecodeStatus::ok || !missing_codec(wic.status) ||
        !libraw_decoder_available()) {
        return wic;
    }

    const LibRawDecodeResult raw = decode_raw_with_libraw(path, limits, stop_token, control);
    if (raw.status != LibRawDecodeStatus::ok) {
        // LibRaw 도 못 읽으면 **WIC 의 실패 사유를 그대로 돌려줍니다.** LibRaw 의 사유로
        // 덮으면 "codec 이 없다" 와 "파일이 깨졌다" 가 뒤섞여 사용자에게 엉뚱한 안내가
        // 나갑니다.
        return wic;
    }

    WicStandardImageDecodeResult result{};
    result.status = WicStandardImageDecodeStatus::ok;
    result.icc_status = negaflow::color::IccProfileStatus::not_present;
    result.info.frame_count = 1U;
    result.info.raw_development_used = true;
    result.info.libraw_fallback_used = true;
    // LibRaw 가 파일의 flip 을 이미 적용해서 돌려줍니다. WIC RAW 경로가
    // `IWICDevelopRaw` 로 as-shot 회전을 적용하고 orientation 을 1 로 두는 것과 같습니다.
    result.info.exif_orientation = 1U;
    result.info.orientation_applied = false;
    result.image = std::move(const_cast<LibRawDecodeResult&>(raw).image);
    // WIC 경로가 디코드하면서 줄이는 것과 같은 자리입니다. LibRaw 는 다 만들어 놓고
    // 돌려주므로 여기서 줄여야 그 뒤 단계 전부가 프리뷰 크기로 돕니다.
    if (shrink_decoded_rgba16(result.image, control)) {
        result.info.reduced_for_preview = true;
    }
    result.info.decoded_pixel_bytes =
        static_cast<std::uint64_t>(result.image.stride_bytes) * result.image.height;
    return result;
}

WicStandardImageDecodeResult decode_standard_image_with_wic_only(
    const std::filesystem::path& path,
    const WicStandardImageDecodeLimits& limits,
    const std::stop_token stop_token,
    const WicStandardImageDecodeControl& control) noexcept {
    WicStandardImageDecodeResult result{};
    try {
        if (path.empty()) {
            return result;
        }
        if (stop_token.stop_requested()) {
            result.status = WicStandardImageDecodeStatus::cancelled;
            return result;
        }
        const ComApartment apartment{};
        if (apartment.status() == RPC_E_CHANGED_MODE) {
            result.status = WicStandardImageDecodeStatus::com_apartment_mismatch;
            return result;
        }
        if (FAILED(apartment.status())) {
            result.status = WicStandardImageDecodeStatus::wic_unavailable;
            return result;
        }

        ComPtr<IWICImagingFactory> factory{};
        if (FAILED(CoCreateInstance(
                CLSID_WICImagingFactory,
                nullptr,
                CLSCTX_INPROC_SERVER,
                IID_PPV_ARGS(&factory)))) {
            result.status = WicStandardImageDecodeStatus::wic_unavailable;
            return result;
        }
        ComPtr<IWICBitmapDecoder> decoder{};
        if (FAILED(factory->CreateDecoderFromFilename(
                path.c_str(),
                nullptr,
                GENERIC_READ,
                WICDecodeMetadataCacheOnDemand,
                &decoder))) {
            result.status = WicStandardImageDecodeStatus::decoder_initialization_failed;
            return result;
        }
        GUID format{};
        if (FAILED(decoder->GetContainerFormat(&format)) || !supported_container(format)) {
            result.status = WicStandardImageDecodeStatus::unsupported_container;
            return result;
        }
        const bool is_raw = IsEqualGUID(format, GUID_ContainerFormatRaw) != 0;
        if (FAILED(decoder->GetFrameCount(&result.info.frame_count)) ||
            result.info.frame_count != 1U) {
            result.status = WicStandardImageDecodeStatus::frame_count_unsupported;
            return result;
        }
        ComPtr<IWICBitmapFrameDecode> frame{};
        UINT width = 0U;
        UINT height = 0U;
        if (FAILED(decoder->GetFrame(0U, &frame))) {
            result.status = WicStandardImageDecodeStatus::pixel_decode_failed;
            return result;
        }
        if (is_raw) {
            const WicStandardImageDecodeStatus raw_status =
                configure_raw_development(factory.Get(), frame.Get());
            if (raw_status != WicStandardImageDecodeStatus::ok) {
                result.status = raw_status;
                return result;
            }
            result.info.raw_development_used = true;
        }
        if (FAILED(frame->GetSize(&width, &height)) || width == 0U || height == 0U) {
            result.status = WicStandardImageDecodeStatus::pixel_decode_failed;
            return result;
        }
        const std::uint64_t stride = static_cast<std::uint64_t>(width) * 8ULL;
        const std::uint64_t bytes = stride * height;
        if (stride > std::numeric_limits<UINT>::max() ||
            bytes > limits.max_decoded_pixel_bytes ||
            bytes > std::numeric_limits<UINT>::max() ||
            bytes / sizeof(std::uint16_t) > std::numeric_limits<std::size_t>::max()) {
            result.status = WicStandardImageDecodeStatus::memory_limit_exceeded;
            return result;
        }
        const WicStandardImageDecodeStatus profile_status =
            extract_icc_profile(factory.Get(), frame.Get(), limits, result);
        if (profile_status != WicStandardImageDecodeStatus::ok) {
            result.status = profile_status;
            return result;
        }
        if (stop_token.stop_requested()) {
            result.status = WicStandardImageDecodeStatus::cancelled;
            return result;
        }
        // WIC RAW codecs apply their as-shot rotation through IWICDevelopRaw. Standard
        // containers retain the EXIF transform here, matching ImageIO's separate path.
        result.info.exif_orientation = is_raw ? 1U : exif_orientation(frame.Get());
        GUID source_format{};
        if (FAILED(frame->GetPixelFormat(&source_format))) {
            result.status = WicStandardImageDecodeStatus::pixel_decode_failed;
            return result;
        }
        ComPtr<IWICBitmapSource> source{};
        if (IsEqualGUID(source_format, GUID_WICPixelFormat64bppRGBA) != 0) {
            if (FAILED(frame.As(&source))) {
                result.status = WicStandardImageDecodeStatus::pixel_decode_failed;
                return result;
            }
        } else {
            ComPtr<IWICFormatConverter> converter{};
            BOOL can_convert = FALSE;
            if (FAILED(factory->CreateFormatConverter(&converter)) ||
                FAILED(converter->CanConvert(source_format, GUID_WICPixelFormat64bppRGBA,
                    &can_convert)) || !can_convert ||
                FAILED(converter->Initialize(
                    frame.Get(),
                    GUID_WICPixelFormat64bppRGBA,
                    WICBitmapDitherTypeNone,
                    nullptr,
                    0.0,
                    WICBitmapPaletteTypeCustom)) ||
                FAILED(converter.As(&source))) {
                result.status = WicStandardImageDecodeStatus::unsupported_pixel_format;
                return result;
            }
            result.info.format_conversion_used = true;
        }
        ComPtr<IWICBitmapSource> oriented{};
        if (!wic_detail::apply_exif_orientation(
                factory.Get(), source.Get(), result.info.exif_orientation, oriented)) {
            result.status = WicStandardImageDecodeStatus::pixel_decode_failed;
            return result;
        }
        if (FAILED(oriented->GetSize(&width, &height)) || width == 0U || height == 0U) {
            result.status = WicStandardImageDecodeStatus::pixel_decode_failed;
            return result;
        }
        // **프리뷰는 원본 전체를 풀지 않습니다.**
        //
        // 실측(2026-08-26, 제조사별 RAW 7 장): 1536x1024 프리뷰 하나를 만들려고 6000x4000
        // 이상을 통째로 디코드해서 사진을 처음 열 때마다 2.2~13.1 초, 7 장에 peak 1,232 MB
        // 였습니다. 사진을 갈아탈 때마다 그 값을 다시 냈습니다.
        //
        // macOS 는 같은 자리에서 `ImageLoader.loadImportedPreview` 가 `CIRAWFilter.scaleFactor`
        // 로 **줄여서** 풉니다(캔버스 정착본도 긴 변 3600, 빠른 프리뷰는 720). 스캐너 TIFF
        // 경로는 이 포트에도 이미 같은 축소가 있었고, 표준·RAW 경로에만 빠져 있었습니다.
        //
        // `IWICBitmapScaler` 는 소스가 `IWICBitmapSourceTransform` 을 내면 그것으로 줄여
        // 풉니다 — RAW codec 이 바로 그런 소스라, 전체를 푼 뒤 줄이는 것이 아니라 처음부터
        // 작게 풉니다.
        if (control.max_output_width > 0U && control.max_output_height > 0U &&
            (width > control.max_output_width || height > control.max_output_height)) {
            UINT fitted_width = width;
            UINT fitted_height = height;
            if (fitted_width > control.max_output_width) {
                fitted_width = control.max_output_width;
                fitted_height = width == 0U
                    ? 0U
                    : static_cast<UINT>(
                          (static_cast<std::uint64_t>(height) * fitted_width) / width);
                if (fitted_height == 0U) fitted_height = 1U;
            }
            if (fitted_height > control.max_output_height) {
                fitted_height = control.max_output_height;
                fitted_width = height == 0U
                    ? 0U
                    : static_cast<UINT>(
                          (static_cast<std::uint64_t>(width) * fitted_height) / height);
                if (fitted_width == 0U) fitted_width = 1U;
            }
            ComPtr<IWICBitmapScaler> scaler{};
            ComPtr<IWICBitmapSource> scaled{};
            if (SUCCEEDED(factory->CreateBitmapScaler(&scaler)) &&
                SUCCEEDED(scaler->Initialize(
                    oriented.Get(),
                    fitted_width,
                    fitted_height,
                    WICBitmapInterpolationModeHighQualityCubic)) &&
                SUCCEEDED(scaler.As(&scaled))) {
                UINT scaled_width = 0U;
                UINT scaled_height = 0U;
                if (SUCCEEDED(scaled->GetSize(&scaled_width, &scaled_height)) &&
                    scaled_width != 0U && scaled_height != 0U) {
                    oriented = scaled;
                    width = scaled_width;
                    height = scaled_height;
                    result.info.reduced_for_preview = true;
                }
            }
            // 스케일러를 못 만들면 원본 크기로 그대로 갑니다 — 느릴 뿐 결과는 옳습니다.
        }
        const std::uint64_t oriented_stride = static_cast<std::uint64_t>(width) * 8ULL;
        const std::uint64_t oriented_bytes = oriented_stride * height;
        if (oriented_stride > std::numeric_limits<UINT>::max() ||
            oriented_bytes > limits.max_decoded_pixel_bytes ||
            oriented_bytes > std::numeric_limits<UINT>::max() ||
            oriented_bytes / sizeof(std::uint16_t) > std::numeric_limits<std::size_t>::max()) {
            result.status = WicStandardImageDecodeStatus::memory_limit_exceeded;
            return result;
        }
        result.image.width = width;
        result.image.height = height;
        result.image.stride_bytes = static_cast<std::uint32_t>(oriented_stride);
        result.image.layout = DecodedPixelLayout::rgba16;
        result.image.alpha_mode = AlphaMode::unassociated;
        result.image.untagged_rgb_transfer = UntaggedRgbTransfer::srgb_encoded;
        result.image.samples.resize(static_cast<std::size_t>(oriented_bytes / sizeof(std::uint16_t)));
        if (FAILED(oriented->CopyPixels(
                nullptr,
                static_cast<UINT>(oriented_stride),
                static_cast<UINT>(oriented_bytes),
                reinterpret_cast<BYTE*>(result.image.samples.data())))) {
            discard_samples(result);
            result.status = WicStandardImageDecodeStatus::pixel_decode_failed;
            return result;
        }
        if (stop_token.stop_requested()) {
            discard_samples(result);
            result.status = WicStandardImageDecodeStatus::cancelled;
            return result;
        }
        result.info.decoded_pixel_bytes = oriented_bytes;
        result.info.orientation_applied = result.info.exif_orientation != 1U;
        result.status = WicStandardImageDecodeStatus::ok;
        return result;
    } catch (const std::bad_alloc&) {
        discard_samples(result);
        result.status = WicStandardImageDecodeStatus::allocation_failed;
        return result;
    } catch (...) {
        discard_samples(result);
        result.status = WicStandardImageDecodeStatus::pixel_decode_failed;
        return result;
    }
}

const char* wic_standard_image_decode_status_name(const WicStandardImageDecodeStatus status) noexcept {
    switch (status) {
        case WicStandardImageDecodeStatus::ok: return "ok";
        case WicStandardImageDecodeStatus::invalid_argument: return "invalid_argument";
        case WicStandardImageDecodeStatus::cancelled: return "cancelled";
        case WicStandardImageDecodeStatus::com_apartment_mismatch: return "com_apartment_mismatch";
        case WicStandardImageDecodeStatus::wic_unavailable: return "wic_unavailable";
        case WicStandardImageDecodeStatus::decoder_initialization_failed:
            return "decoder_initialization_failed";
        case WicStandardImageDecodeStatus::unsupported_container: return "unsupported_container";
        case WicStandardImageDecodeStatus::frame_count_unsupported:
            return "frame_count_unsupported";
        case WicStandardImageDecodeStatus::raw_development_failed:
            return "raw_development_failed";
        case WicStandardImageDecodeStatus::unsupported_pixel_format:
            return "unsupported_pixel_format";
        case WicStandardImageDecodeStatus::color_context_failed: return "color_context_failed";
        case WicStandardImageDecodeStatus::invalid_icc_profile: return "invalid_icc_profile";
        case WicStandardImageDecodeStatus::memory_limit_exceeded: return "memory_limit_exceeded";
        case WicStandardImageDecodeStatus::allocation_failed: return "allocation_failed";
        case WicStandardImageDecodeStatus::pixel_decode_failed: return "pixel_decode_failed";
    }
    return "unknown_standard_image_decode_status";
}

}  // namespace negaflow::imageio
