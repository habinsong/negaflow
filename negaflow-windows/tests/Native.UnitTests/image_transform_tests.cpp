#include "negaflow/imaging/image_transform.h"
#include "negaflow/imaging/perspective_geometry.h"

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

// 프리뷰 발행은 회전·뒤집기·자르기를 **화소를 옮겨 담지 않고** 읽는 자리만 바꿔
// 처리합니다(`plan_image_transform_gather` → `shaders/preview_display_encode.hlsl`).
// 그 자리 계산이 `apply_image_transform` 과 **한 화소라도** 다르면 자른 자리가 어긋난
// 사진이 나옵니다. 회전 넷 × 뒤집기 넷 × 자르기 유무를 전부 대조합니다.
void test_gather_matches_apply_for_every_orientation() {
    const negaflow::imaging::WorkingImage source = marker_image();
    const negaflow::imaging::ImageRotation rotations[] = {
        negaflow::imaging::ImageRotation::degrees_0,
        negaflow::imaging::ImageRotation::degrees_90,
        negaflow::imaging::ImageRotation::degrees_180,
        negaflow::imaging::ImageRotation::degrees_270,
    };
    const negaflow::imaging::NormalizedCropRect crops[] = {
        {0.0, 0.0, 1.0, 1.0},
        {0.25, 0.0, 0.5, 1.0},
        {0.0, 0.34, 1.0, 0.66},
        {0.25, 0.25, 0.5, 0.5},
    };
    for (const negaflow::imaging::ImageRotation rotation : rotations) {
        for (int flips = 0; flips < 4; ++flips) {
            for (int crop_index = 0; crop_index < 5; ++crop_index) {
                negaflow::imaging::ImageTransformParameters parameters{};
                parameters.rotation = rotation;
                parameters.flip_horizontal = (flips & 1) != 0;
                parameters.flip_vertical = (flips & 2) != 0;
                parameters.has_crop = crop_index > 0;
                if (parameters.has_crop) {
                    parameters.crop = crops[crop_index - 1];
                }
                negaflow::imaging::ImageTransformGather gather{};
                if (!negaflow::imaging::plan_image_transform_gather(
                        parameters, source.width, source.height, gather)) {
                    expect(false, "a straighten-free transform must plan a gather");
                    continue;
                }
                const auto applied =
                    negaflow::imaging::apply_image_transform(source, parameters);
                expect(
                    applied.status == negaflow::imaging::ImageTransformStatus::ok,
                    "the CPU transform must succeed");
                expect(
                    gather.output_width == applied.image.width &&
                        gather.output_height == applied.image.height,
                    "the gather plan must agree on the output extent");
                if (gather.output_width != applied.image.width ||
                    gather.output_height != applied.image.height) {
                    continue;
                }
                // 셰이더 `SourceCoordinate` 와 같은 식입니다.
                bool same = true;
                for (std::uint32_t y = 0U; y < gather.output_height && same; ++y) {
                    for (std::uint32_t x = 0U; x < gather.output_width; ++x) {
                        const std::uint32_t ox_o = x + gather.crop_left;
                        const std::uint32_t oy_o = y + gather.crop_top;
                        std::uint32_t ox = ox_o;
                        std::uint32_t oy = oy_o;
                        switch (gather.rotation) {
                            case negaflow::imaging::ImageRotation::degrees_0:
                                break;
                            case negaflow::imaging::ImageRotation::degrees_90:
                                ox = oy_o;
                                oy = source.height - 1U - ox_o;
                                break;
                            case negaflow::imaging::ImageRotation::degrees_180:
                                ox = source.width - 1U - ox_o;
                                oy = source.height - 1U - oy_o;
                                break;
                            case negaflow::imaging::ImageRotation::degrees_270:
                                ox = source.width - 1U - oy_o;
                                oy = ox_o;
                                break;
                        }
                        if (gather.flip_horizontal) {
                            ox = source.width - 1U - ox;
                        }
                        if (gather.flip_vertical) {
                            oy = source.height - 1U - oy;
                        }
                        const negaflow::core::Rgba32F gathered = source.pixels[
                            static_cast<std::size_t>(oy) * source.stride_pixels + ox];
                        const negaflow::core::Rgba32F expected = applied.image.pixels[
                            static_cast<std::size_t>(y) * applied.image.stride_pixels + x];
                        if (gathered.red != expected.red ||
                            gathered.green != expected.green ||
                            gathered.blue != expected.blue ||
                            gathered.alpha != expected.alpha) {
                            same = false;
                            break;
                        }
                    }
                }
                expect(same, "the gather must read the same pixel the CPU transform wrote");
            }
        }
    }
}

void test_gather_refuses_straighten() {
    negaflow::imaging::ImageTransformParameters parameters{};
    parameters.straighten_angle = 3.0;
    negaflow::imaging::ImageTransformGather gather{};
    expect(
        !negaflow::imaging::plan_image_transform_gather(parameters, 64U, 48U, gather),
        "straighten is bilinear and must fall back to the CPU transform");
    parameters.perspective.active = true;
    parameters.perspective.vertical = 20.0;
    expect(
        !negaflow::imaging::plan_image_transform_gather(parameters, 64U, 48U, gather),
        "perspective plus straighten reads twice on the CPU and must not be planned as one read");
}

// 원근만 있으면 발행 커널이 한 번 읽기로 처리합니다. 출력 크기와 자르기 자리가 CPU 와 같아야
// 합니다(자르기 제한으로 출력 사각형이 줄어드는 경우 포함).
void test_gather_plans_perspective_like_the_cpu() {
    negaflow::imaging::WorkingImage image{};
    image.width = 300U;
    image.height = 200U;
    image.stride_pixels = image.width;
    image.pixels.assign(static_cast<std::size_t>(image.width) * image.height, {0.3F, 0.4F, 0.5F, 1.0F});
    for (const bool constrain : {false, true}) {
        negaflow::imaging::ImageTransformParameters parameters{};
        parameters.rotation = negaflow::imaging::ImageRotation::degrees_270;
        parameters.flip_vertical = true;
        parameters.has_crop = true;
        parameters.crop = {0.1, 0.05, 0.8, 0.9};
        parameters.perspective.active = true;
        parameters.perspective.vertical = 25.0;
        parameters.perspective.constrain_crop = constrain;
        negaflow::imaging::ImageTransformGather gather{};
        const bool planned = negaflow::imaging::plan_image_transform_gather(
            parameters, image.width, image.height, gather);
        const auto applied = negaflow::imaging::apply_image_transform(image, parameters);
        expect(planned && gather.perspective, "a perspective-only transform plans a gather");
        expect(applied.status == negaflow::imaging::ImageTransformStatus::ok &&
                   gather.output_width == applied.image.width &&
                   gather.output_height == applied.image.height,
               "the perspective gather agrees with the CPU extent");
        expect(gather.oriented_width == image.height && gather.oriented_height == image.width,
               "the perspective is solved on the oriented image");
    }
}

// 변환(원근)을 걸어도 그림 중심은 프레임 가운데에 남고, 정·역 호모그래피가 서로의 역입니다.
// macOS PerspectiveCorrectionTests 와 같은 값입니다.
void test_perspective_keeps_center_and_round_trips() {
    using negaflow::imaging::PerspectiveParameters;
    using negaflow::imaging::PerspectivePoint;
    PerspectiveParameters tilted{};
    tilted.active = true;
    tilted.solved_vertical = -15.0;
    tilted.solved_horizontal = 5.0;
    tilted.solved_rotate = 2.0;
    const auto mapping = negaflow::imaging::make_perspective_mapping(tilted, 2400.0, 1600.0);
    expect(mapping.has_value(), "perspective mapping exists for a valid tilt");
    if (!mapping.has_value()) {
        return;
    }
    const auto center = negaflow::imaging::apply_homography(mapping->forward, PerspectivePoint{1200.0, 800.0});
    expect(center.has_value() && std::abs(center->x - 1200.0) < 1.0e-6 && std::abs(center->y - 800.0) < 1.0e-6,
           "perspective keeps the photo center at the frame center");
    bool round_trip = true;
    for (const PerspectivePoint point : {PerspectivePoint{0.0, 0.0}, PerspectivePoint{2400.0, 0.0},
                                         PerspectivePoint{2400.0, 1600.0}, PerspectivePoint{0.0, 1600.0},
                                         PerspectivePoint{333.0, 517.0}}) {
        const auto forward = negaflow::imaging::apply_homography(mapping->forward, point);
        const auto back = forward.has_value()
            ? negaflow::imaging::apply_homography(mapping->inverse, *forward)
            : std::nullopt;
        round_trip = round_trip && back.has_value() && std::abs(back->x - point.x) < 1.0e-6 &&
                     std::abs(back->y - point.y) < 1.0e-6;
    }
    expect(round_trip, "perspective forward and inverse round trip");
    PerspectiveParameters identity{};
    identity.active = true;
    expect(!negaflow::imaging::make_perspective_mapping(identity, 2400.0, 1600.0).has_value(),
           "identity perspective leaves the image alone");
}

// 원근 보정의 빈 곳: 내보내기는 불투명 흰색, 프리뷰는 같은 흰색에 커버리지 0 — 사진 부분은 같습니다.
void test_perspective_uncovered_fill() {
    negaflow::imaging::WorkingImage image{};
    image.width = 240U;
    image.height = 160U;
    image.stride_pixels = image.width;
    image.pixels.assign(static_cast<std::size_t>(image.width) * image.height, {0.2F, 0.3F, 0.4F, 1.0F});
    negaflow::imaging::ImageTransformParameters parameters{};
    parameters.perspective.active = true;
    parameters.perspective.vertical = 40.0;
    expect(negaflow::imaging::perspective_leaves_uncovered_area(parameters.perspective),
           "an unconstrained perspective leaves an uncovered area");
    const auto opaque = negaflow::imaging::apply_image_transform(image, parameters);
    parameters.uncovered_fill = negaflow::imaging::UncoveredFill::white_without_coverage;
    const auto preview = negaflow::imaging::apply_image_transform(image, parameters);
    expect(opaque.status == negaflow::imaging::ImageTransformStatus::ok &&
               preview.status == negaflow::imaging::ImageTransformStatus::ok &&
               opaque.image.width == image.width && preview.image.height == image.height,
           "both fills keep the canvas size");
    // 위가 넓어지면 아래 모서리가 빕니다(행 0 = 위).
    const std::size_t bottom_left = static_cast<std::size_t>(image.height - 1U) * image.width;
    const std::size_t center = static_cast<std::size_t>(image.height / 2U) * image.width + image.width / 2U;
    const auto& opaque_corner = opaque.image.pixels[bottom_left];
    const auto& preview_corner = preview.image.pixels[bottom_left];
    expect(opaque_corner.red == 1.0F && opaque_corner.alpha == 1.0F,
           "export fill is opaque white");
    expect(preview_corner.red == 1.0F && preview_corner.alpha == 0.0F,
           "preview fill is white without coverage");
    expect(std::abs(preview.image.pixels[center].blue - opaque.image.pixels[center].blue) < 1.0e-6F &&
               preview.image.pixels[center].alpha == 1.0F,
           "photo pixels do not depend on the fill");
    parameters.perspective.constrain_crop = true;
    expect(!negaflow::imaging::perspective_leaves_uncovered_area(parameters.perspective),
           "constrain crop leaves no uncovered area");
}

} // namespace

int main() {
    test_identity_and_quarter_turn();
    test_flip_then_crop_uses_y_up_recipe();
    test_straighten_preserves_alpha_and_fails_closed();
    test_positive_straighten_rotates_clockwise();
    test_gather_matches_apply_for_every_orientation();
    test_gather_refuses_straighten();
    test_gather_plans_perspective_like_the_cpu();
    test_perspective_keeps_center_and_round_trips();
    test_perspective_uncovered_fill();
    if (failures == 0) {
        std::cout << "image transform tests passed\n";
    }
    return failures == 0 ? 0 : 1;
}
