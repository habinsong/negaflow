#pragma once

#include <Windows.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <cstdint>

namespace negaflow::imageio::wic_detail {

[[nodiscard]] bool apply_exif_orientation(
    IWICImagingFactory* factory,
    IWICBitmapSource* source,
    std::uint16_t orientation,
    Microsoft::WRL::ComPtr<IWICBitmapSource>& oriented) noexcept;

}  // namespace negaflow::imageio::wic_detail
