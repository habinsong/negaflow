#include "negaflow/imaging/image_transform.h"

#include <cmath>
#include <cstring>
#include <iostream>
#include <limits>
#include <vector>

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

[[nodiscard]] negaflow::imaging::WorkingImage marker_image() {
    negaflow::imaging::WorkingImage image{};
    image.width = 4U;
    image.height = 3U;
    image.stride_pixels = image.width;
    image.pixels.resize(12U);
    for (std::uint32_t y = 0U; y < image.height; ++y) {
        for (std::uint32_t x = 0U; x < image.width; ++x) {
            image.pixels[static_cast<std::size_t>(y) * image.width + x] = {
                static_cast<float>(y * 10U + x),
                static_cast<float>(x),
                static_cast<float>(y),
                0.2F + 0.1F * static_cast<float>(x),
            };
        }
    }
    return image;
}

[[nodiscard]] bool same_pixels(
    const std::vector<negaflow::core::Rgba32F>& left,
    const std::vector<negaflow::core::Rgba32F>& right) noexcept {
    return left.size() == right.size() &&
           std::memcmp(left.data(), right.data(),
                       left.size() * sizeof(left.front())) == 0;
}

void test_identity_and_quarter_turn() {
    const auto source = marker_image();
    const auto identity = negaflow::imaging::apply_image_transform(source, {});
    expect(
        identity.status == negaflow::imaging::ImageTransformStatus::ok &&
            !identity.info.applied && same_pixels(identity.image.pixels, source.pixels),
        "identity transform is byte exact");

    negaflow::imaging::ImageTransformParameters rotation{};
    rotation.rotation = negaflow::imaging::ImageRotation::degrees_90;
    const auto rotated = negaflow::imaging::apply_image_transform(source, rotation);
    expect(
        rotated.image.width == 3U && rotated.image.height == 4U &&
            rotated.image.pixels[0].red == 20.0F &&
            rotated.image.pixels[2].red == 0.0F &&
            rotated.image.pixels[9].red == 23.0F,
        "90-degree rotation uses the macOS clockwise mapping");
}

void test_flip_then_crop_uses_y_up_recipe() {
    negaflow::imaging::ImageTransformParameters transform{};
    transform.flip_horizontal = true;
    transform.has_crop = true;
    transform.crop = {0.0, 0.0, 0.5, 2.0 / 3.0};
    const auto result = negaflow::imaging::apply_image_transform(
        marker_image(), transform);
    expect(
        result.status == negaflow::imaging::ImageTransformStatus::ok &&
            result.image.width == 2U && result.image.height == 2U &&
            result.image.pixels[0].red == 13.0F &&
            result.image.pixels[2].red == 23.0F,
        "crop is last and converts persisted y-up coordinates once");
}

void test_straighten_preserves_alpha_and_fails_closed() {
    auto source = marker_image();
    for (auto& pixel : source.pixels) {
        pixel.alpha = 0.37F;
    }
    negaflow::imaging::ImageTransformParameters transform{};
    transform.straighten_angle = 10.0;
    const auto result = negaflow::imaging::apply_image_transform(source, transform);
    bool alpha_preserved = result.info.resampled;
    for (const auto pixel : result.image.pixels) {
        alpha_preserved = alpha_preserved && std::abs(pixel.alpha - 0.37F) < 1.0e-6F;
    }
    expect(alpha_preserved, "straighten resamples alpha with the image");

    transform.straighten_angle = std::numeric_limits<double>::quiet_NaN();
    const auto rejected = negaflow::imaging::apply_image_transform(source, transform);
    expect(
        rejected.status ==
                negaflow::imaging::ImageTransformStatus::invalid_parameter &&
            rejected.image.pixels.empty(),
        "non-finite transform recipe fails closed");
}

void test_positive_straighten_rotates_clockwise() {
    negaflow::imaging::WorkingImage image{};
    image.width = 41U;
    image.height = 41U;
    image.stride_pixels = image.width;
    image.pixels.resize(41U * 41U, {0.0F, 0.0F, 0.0F, 1.0F});
    image.pixels[20U * 41U + 30U] = {1.0F, 1.0F, 1.0F, 1.0F};
    negaflow::imaging::ImageTransformParameters transform{};
    transform.straighten_angle = 10.0;
    const auto result = negaflow::imaging::apply_image_transform(image, transform);
    std::size_t brightest = 0U;
    for (std::size_t index = 1U; index < result.image.pixels.size(); ++index) {
        if (result.image.pixels[index].red > result.image.pixels[brightest].red) {
            brightest = index;
        }
    }
    const std::uint32_t y = static_cast<std::uint32_t>(
        brightest / result.image.width);
    expect(
        y > result.image.height / 2U,
        "positive straighten rotates a right-side marker clockwise");
}

}  // namespace

int main() {
    test_identity_and_quarter_turn();
    test_flip_then_crop_uses_y_up_recipe();
    test_straighten_preserves_alpha_and_fails_closed();
    test_positive_straighten_rotates_clockwise();
    return failures == 0 ? 0 : 1;
}
