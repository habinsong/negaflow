#include "negaflow/imageio/libraw_preview_reduce.h"

#include <cmath>
#include <cstdint>
#include <iostream>
#include <vector>

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

constexpr std::uint64_t generous_pixel_budget = 8ULL * 1024ULL * 1024ULL * 1024ULL;

/// 왼쪽에서 오른쪽으로 밝아지는 세로 줄무늬입니다. 평균과 보간이 값을 어디로 옮기는지
/// 눈으로 확인할 수 있는 가장 단순한 그림입니다.
[[nodiscard]] std::vector<std::uint16_t> ramp(
    const std::uint32_t width,
    const std::uint32_t height) {
    std::vector<std::uint16_t> samples(
        static_cast<std::size_t>(width) * height * 3U);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const std::size_t at = (static_cast<std::size_t>(y) * width + x) * 3U;
            const auto value = static_cast<std::uint16_t>(
                (static_cast<std::uint32_t>(x) * 65'535U) / (width > 1U ? width - 1U : 1U));
            samples[at] = value;
            samples[at + 1U] = value;
            samples[at + 2U] = value;
        }
    }
    return samples;
}

void reduces_to_the_requested_box() {
    const std::uint32_t width = 10'056U;
    const std::uint32_t height = 6'792U;
    const std::vector<std::uint16_t> source = ramp(width, height);
    negaflow::imageio::DecodedImage image{};
    const auto result = negaflow::imageio::reduce_libraw_rgb16_to_preview(
        source.data(), width, height, 2'560U, 2'560U, generous_pixel_budget, image);
    expect(result.ok, "68.3 MP source reduces");
    expect(result.reduced, "reduction is reported");
    // 10056 / 2560 = 3 (내림). 정수 3배 평균을 먼저 하고 그 뒤 WIC 가 마무리합니다.
    expect(result.box_average_factor == 3U, "integer pre-reduction is 3x");
    expect(image.width == 2'560U, "fitted width");
    expect(image.height == 1'729U, "fitted height keeps the aspect");
    expect(image.layout == negaflow::imageio::DecodedPixelLayout::rgba16, "rgba16 layout");
    expect(image.stride_bytes == 2'560U * 8U, "stride is 8 bytes per pixel");
    expect(
        image.samples.size() ==
            static_cast<std::size_t>(image.width) * image.height * 4U,
        "sample count matches the fitted size");
}

void keeps_the_ramp_direction_and_alpha() {
    const std::uint32_t width = 4'000U;
    const std::uint32_t height = 3'000U;
    const std::vector<std::uint16_t> source = ramp(width, height);
    negaflow::imageio::DecodedImage image{};
    const auto result = negaflow::imageio::reduce_libraw_rgb16_to_preview(
        source.data(), width, height, 1'000U, 1'000U, generous_pixel_budget, image);
    expect(result.ok, "4000x3000 source reduces");
    expect(result.box_average_factor == 4U, "integer pre-reduction is 4x");
    expect(image.width == 1'000U && image.height == 750U, "fitted size");

    const std::size_t row = static_cast<std::size_t>(image.height / 2U) * image.width * 4U;
    const std::uint16_t left = image.samples[row + 4U];
    const std::uint16_t right = image.samples[row + (static_cast<std::size_t>(image.width) - 2U) * 4U];
    expect(left < right, "the ramp still rises to the right");
    expect(image.samples[row + 3U] == 65'535U, "alpha is opaque");
    // 회색 줄무늬는 세 채널이 같아야 합니다. 채널이 어긋나면 색이 밀린 것입니다.
    expect(
        image.samples[row] == image.samples[row + 1U] &&
            image.samples[row + 1U] == image.samples[row + 2U],
        "grey stays grey across channels");
}

void covers_the_whole_frame_when_the_factor_does_not_divide() {
    // 4001 은 3 으로 나누어떨어지지 않습니다. 가장자리 칸을 버리면 오른쪽 끝의 가장 밝은
    // 화소가 사라집니다 - 그 자리가 이 시험의 목적입니다.
    const std::uint32_t width = 4'001U;
    const std::uint32_t height = 2'001U;
    const std::vector<std::uint16_t> source = ramp(width, height);
    negaflow::imageio::DecodedImage image{};
    const auto result = negaflow::imageio::reduce_libraw_rgb16_to_preview(
        source.data(), width, height, 1'000U, 1'000U, generous_pixel_budget, image);
    expect(result.ok, "odd size reduces");
    expect(result.box_average_factor >= 2U, "still pre-reduces");
    const std::size_t row = static_cast<std::size_t>(image.height / 2U) * image.width * 4U;
    const std::uint16_t last = image.samples[row + (static_cast<std::size_t>(image.width) - 1U) * 4U];
    expect(last > 60'000U, "the brightest edge survives the reduction");
}

void passes_through_when_no_box_is_requested() {
    const std::uint32_t width = 64U;
    const std::uint32_t height = 48U;
    const std::vector<std::uint16_t> source = ramp(width, height);
    negaflow::imageio::DecodedImage image{};
    const auto result = negaflow::imageio::reduce_libraw_rgb16_to_preview(
        source.data(), width, height, 0U, 0U, generous_pixel_budget, image);
    expect(result.ok, "no box still succeeds");
    expect(!result.reduced, "nothing was reduced");
    expect(result.box_average_factor == 1U, "no pre-reduction");
    expect(image.width == width && image.height == height, "original size");
    for (std::uint32_t x = 0U; x < width; ++x) {
        const std::size_t in = static_cast<std::size_t>(x) * 3U;
        const std::size_t out = static_cast<std::size_t>(x) * 4U;
        if (image.samples[out] != source[in] || image.samples[out + 3U] != 65'535U) {
            expect(false, "pass-through copies the samples exactly");
            return;
        }
    }
}

void refuses_a_budget_it_cannot_meet() {
    const std::uint32_t width = 4'000U;
    const std::uint32_t height = 3'000U;
    const std::vector<std::uint16_t> source = ramp(width, height);
    negaflow::imageio::DecodedImage image{};
    const auto result = negaflow::imageio::reduce_libraw_rgb16_to_preview(
        source.data(), width, height, 0U, 0U, 1'024ULL, image);
    expect(!result.ok, "a budget smaller than the result is refused");
}

void refuses_empty_input() {
    negaflow::imageio::DecodedImage image{};
    const auto empty = negaflow::imageio::reduce_libraw_rgb16_to_preview(
        nullptr, 16U, 16U, 8U, 8U, generous_pixel_budget, image);
    expect(!empty.ok, "null source is refused");
    const std::vector<std::uint16_t> source = ramp(4U, 4U);
    const auto zero = negaflow::imageio::reduce_libraw_rgb16_to_preview(
        source.data(), 0U, 4U, 2U, 2U, generous_pixel_budget, image);
    expect(!zero.ok, "zero width is refused");
}

}  // namespace

int main() {
    reduces_to_the_requested_box();
    keeps_the_ramp_direction_and_alpha();
    covers_the_whole_frame_when_the_factor_does_not_divide();
    passes_through_when_no_box_is_requested();
    refuses_a_budget_it_cannot_meet();
    refuses_empty_input();
    if (failures == 0) {
        std::cout << "libraw_preview_reduce: all checks passed\n";
    }
    return failures == 0 ? 0 : 1;
}
