#include "negaflow/imaging/analysis_region.h"
#include "negaflow/imaging/mipmap_downsampler.h"

#include <cmath>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <vector>

namespace {

using negaflow::imaging::AnalysisPixelRect;
using negaflow::imaging::ImageRotation;
using negaflow::imaging::ImageTransformParameters;

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

[[nodiscard]] bool near(const double actual, const double expected, const double tolerance = 1.0e-9) {
    return std::abs(actual - expected) <= tolerance;
}

// macOS CameraScanMeasurementTests 와 같은 크롭 — 1500x1000 의 사진 영역 140..1360 x 170..830(y-down).
[[nodiscard]] ImageTransformParameters camera_scan_crop() {
    ImageTransformParameters transform{};
    transform.has_crop = true;
    transform.crop = {140.0 / 1500.0, (1000.0 - 830.0) / 1000.0, 1220.0 / 1500.0, 660.0 / 1000.0};
    return transform;
}

void test_region_follows_crop_and_straighten() {
    const auto crop = negaflow::imaging::analysis_region_from_transform(camera_scan_crop(), 1500U, 1000U);
    expect(crop.has_value(), "crop makes a region");
    if (crop) {
        expect(near(crop->left, 140.0 / 1500.0), "crop left");
        expect(near(crop->top, 170.0 / 1000.0), "crop top (y-down)");
        expect(near(crop->width, 1220.0 / 1500.0), "crop width");
        expect(near(crop->height, 660.0 / 1000.0), "crop height");
    }

    ImageTransformParameters rotated{};
    rotated.rotation = ImageRotation::degrees_90;
    rotated.flip_horizontal = true;
    expect(!negaflow::imaging::analysis_region_from_transform(rotated, 1500U, 1000U).has_value(),
           "rotation and flip alone make no region");

    ImageTransformParameters tilted = camera_scan_crop();
    tilted.straighten_angle = 3.0;
    const auto tilted_region = negaflow::imaging::analysis_region_from_transform(tilted, 1500U, 1000U);
    expect(tilted_region.has_value(), "straightened crop makes a region");
    if (tilted_region && crop) {
        expect(tilted_region->left >= 0.0 && tilted_region->top >= 0.0 &&
                   tilted_region->left + tilted_region->width <= 1.0 &&
                   tilted_region->top + tilted_region->height <= 1.0,
               "straightened region stays inside the frame");
        expect(tilted_region->width < crop->width + 1.0e-9, "straightened region is not wider than the crop");
    }

    ImageTransformParameters whole{};
    whole.has_crop = true;
    whole.crop = {0.0, 0.0, 1.0, 1.0};
    expect(!negaflow::imaging::analysis_region_from_transform(whole, 1500U, 1000U).has_value(),
           "a whole-frame crop is no region");
}

void test_measurement_rect() {
    const auto region = negaflow::imaging::analysis_region_from_transform(camera_scan_crop(), 1500U, 1000U);
    const auto rect = negaflow::imaging::analysis_measurement_rect(region, 1500U, 1000U);
    expect(rect.has_value(), "rect exists");
    if (rect) {
        expect(rect->x == 140U && rect->y == 170U && rect->width == 1220U && rect->height == 660U,
               "rect matches the photo area in pixels");
    }
    // 같은 비율의 축소 프록시에서도 같은 자리입니다.
    const auto proxy_rect = negaflow::imaging::analysis_measurement_rect(region, 750U, 500U);
    expect(proxy_rect && proxy_rect->x == 70U && proxy_rect->y == 85U &&
               proxy_rect->width == 610U && proxy_rect->height == 330U,
           "rect scales with the proxy");
    expect(!negaflow::imaging::analysis_measurement_rect(region, 10U, 10U).has_value(),
           "a rect of eight pixels or less measures the whole image");
    expect(!negaflow::imaging::analysis_measurement_rect(std::nullopt, 1500U, 1000U).has_value(),
           "no region, no rect");
}

[[nodiscard]] std::vector<negaflow::core::Rgba32F> gradient(const std::uint32_t width, const std::uint32_t height) {
    std::vector<negaflow::core::Rgba32F> pixels(static_cast<std::size_t>(width) * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const float fx = static_cast<float>(x) / static_cast<float>(width);
            const float fy = static_cast<float>(y) / static_cast<float>(height);
            pixels[static_cast<std::size_t>(y) * width + x] = {
                fx, fy, 0.5F * (fx + fy) + 0.1F * std::sin(static_cast<float>(x * 7U + y * 3U)), 1.0F};
        }
    }
    return pixels;
}

// 사각형 원점이 밉맵 단계에 맞춰 있고 끝이 원본 끝과 같으면, 사각형 축소는 잘라낸 사본을
// 축소한 것과 비트 단위로 같습니다 — 전체 화상의 밉맵과 사본의 밉맵이 같은 화소를 묶습니다.
void test_region_downsample_matches_cropped_copy() {
    constexpr std::uint32_t width = 1000U;
    constexpr std::uint32_t height = 700U;
    const auto pixels = gradient(width, height);
    const negaflow::core::ConstImageView full{pixels.data(), pixels.size(), width, height, width};
    const AnalysisPixelRect rect{200U, 96U, width - 200U, height - 96U};

    std::vector<negaflow::core::Rgba32F> copy(static_cast<std::size_t>(rect.width) * rect.height);
    for (std::uint32_t y = 0U; y < rect.height; ++y) {
        std::memcpy(copy.data() + static_cast<std::size_t>(y) * rect.width,
                    pixels.data() + static_cast<std::size_t>(y + rect.y) * width + rect.x,
                    rect.width * sizeof(negaflow::core::Rgba32F));
    }
    const negaflow::core::ConstImageView cropped{copy.data(), copy.size(), rect.width, rect.height, rect.width};

    for (const std::uint32_t target : {100U, 200U, 320U, 800U}) {
        const std::uint32_t target_height = static_cast<std::uint32_t>(
            static_cast<double>(rect.height) * target / rect.width);
        const auto region = negaflow::imaging::downsample_region_for_statistics(full, rect, target, target_height);
        const auto reference = negaflow::imaging::downsample_for_statistics(cropped, target, target_height);
        expect(region.pixels.size() == reference.pixels.size() && !region.pixels.empty(), "same proxy size");
        bool identical = region.pixels.size() == reference.pixels.size();
        for (std::size_t index = 0U; identical && index < region.pixels.size(); ++index) {
            identical = region.pixels[index].red == reference.pixels[index].red &&
                        region.pixels[index].green == reference.pixels[index].green &&
                        region.pixels[index].blue == reference.pixels[index].blue;
        }
        expect(identical, "aligned region proxy equals the cropped copy's proxy");
    }
    expect(negaflow::imaging::downsample_region_for_statistics(
               full, AnalysisPixelRect{900U, 0U, 200U, 10U}, 10U, 1U).pixels.empty(),
           "a rect outside the image is refused");
}

}  // namespace

int main() {
    test_region_follows_crop_and_straighten();
    test_measurement_rect();
    test_region_downsample_matches_cropped_copy();
    if (failures != 0) {
        std::cerr << failures << " analysis region test(s) failed\n";
        return 1;
    }
    std::cout << "analysis region tests passed\n";
    return 0;
}
