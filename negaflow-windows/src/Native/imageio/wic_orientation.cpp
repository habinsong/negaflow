#include "wic_orientation.h"

namespace negaflow::imageio::wic_detail {

bool apply_exif_orientation(
    IWICImagingFactory* const factory,
    IWICBitmapSource* const source,
    const std::uint16_t orientation,
    Microsoft::WRL::ComPtr<IWICBitmapSource>& oriented) noexcept {
    if (factory == nullptr || source == nullptr || orientation < 1U || orientation > 8U) {
        return false;
    }
    oriented = source;
    const auto transform = [&](const WICBitmapTransformOptions option) noexcept {
        if (option == WICBitmapTransformRotate0) return true;
        Microsoft::WRL::ComPtr<IWICBitmapFlipRotator> rotator{};
        return SUCCEEDED(factory->CreateBitmapFlipRotator(&rotator)) &&
            SUCCEEDED(rotator->Initialize(oriented.Get(), option)) &&
            SUCCEEDED(rotator.As(&oriented));
    };
    switch (orientation) {
        case 1U: return true;
        case 2U: return transform(WICBitmapTransformFlipHorizontal);
        case 3U: return transform(WICBitmapTransformRotate180);
        case 4U: return transform(WICBitmapTransformFlipVertical);
        case 5U:
            return transform(WICBitmapTransformRotate90) &&
                transform(WICBitmapTransformFlipHorizontal);
        case 6U: return transform(WICBitmapTransformRotate90);
        case 7U:
            return transform(WICBitmapTransformRotate90) &&
                transform(WICBitmapTransformFlipVertical);
        case 8U: return transform(WICBitmapTransformRotate270);
        default: return false;
    }
}

}  // namespace negaflow::imageio::wic_detail
