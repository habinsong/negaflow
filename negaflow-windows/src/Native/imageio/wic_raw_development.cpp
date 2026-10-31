#include "wic_raw_development.h"

#include <wrl/client.h>

#include <algorithm>
#include <cwctype>
#include <mutex>
#include <string>
#include <vector>

namespace negaflow::imageio::wic_detail {
namespace {

using Microsoft::WRL::ComPtr;

std::mutex g_unavailable_lock{};
std::vector<std::wstring> g_unavailable_extensions{};

[[nodiscard]] std::wstring extension_key(const std::filesystem::path& path) {
    std::wstring key = path.extension().wstring();
    std::transform(key.begin(), key.end(), key.begin(), [](const wchar_t c) {
        return static_cast<wchar_t>(std::towlower(c));
    });
    return key;
}

void remember_unavailable(const std::filesystem::path& path) noexcept {
    try {
        std::wstring key = extension_key(path);
        if (key.empty()) {
            return;
        }
        const std::lock_guard<std::mutex> guard{g_unavailable_lock};
        if (std::find(g_unavailable_extensions.begin(), g_unavailable_extensions.end(), key) ==
            g_unavailable_extensions.end()) {
            g_unavailable_extensions.push_back(std::move(key));
        }
    } catch (...) {
        // 기억하지 못하면 다음 파일도 WIC 를 한 번 거칠 뿐입니다.
    }
}

}  // namespace

WicStandardImageDecodeStatus configure_raw_development(
    IWICImagingFactory* const factory,
    IWICBitmapFrameDecode* const frame,
    const std::filesystem::path& path) noexcept {
    ComPtr<IWICDevelopRaw> raw{};
    if (FAILED(frame->QueryInterface(IID_PPV_ARGS(&raw)))) {
        remember_unavailable(path);
        return WicStandardImageDecodeStatus::raw_development_failed;
    }
    if (FAILED(raw->LoadParameterSet(WICAsShotParameterSet)) ||
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

bool has_camera_raw_extension(const std::filesystem::path& path) noexcept {
    // LibRaw 가 읽는 흔한 카메라 RAW 확장자입니다. 목록에 없으면 예전처럼 WIC 를 먼저 봅니다 —
    // 빠지는 것은 속도뿐이고 결과는 같습니다.
    static constexpr const wchar_t* extensions[] = {
        L".3fr", L".ari", L".arw", L".cr2", L".cr3", L".crw", L".dcr", L".dng", L".erf", L".fff",
        L".iiq", L".k25", L".kdc", L".mdc", L".mef", L".mos", L".mrw", L".nef", L".nrw", L".orf",
        L".pef", L".raf", L".raw", L".rw2", L".rwl", L".sr2", L".srf", L".srw", L".x3f",
    };
    try {
        const std::wstring key = extension_key(path);
        return std::any_of(std::begin(extensions), std::end(extensions),
            [&key](const wchar_t* extension) { return key == extension; });
    } catch (...) {
        return false;
    }
}

bool raw_development_known_unavailable(const std::filesystem::path& path) noexcept {
    try {
        const std::wstring key = extension_key(path);
        const std::lock_guard<std::mutex> guard{g_unavailable_lock};
        return !key.empty() &&
            std::find(g_unavailable_extensions.begin(), g_unavailable_extensions.end(), key) !=
                g_unavailable_extensions.end();
    } catch (...) {
        return false;
    }
}

}  // namespace negaflow::imageio::wic_detail
