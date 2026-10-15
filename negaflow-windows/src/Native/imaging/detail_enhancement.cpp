#include "detail_enhancement.h"

#include "texture_stage_gaussian.h"

#include "negaflow/core/parallel_rows.h"
#include "negaflow/imaging/coreimage_gaussian.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace negaflow::imaging::texture_stage_detail {
namespace {

constexpr float reference_long_side = 6000.0F;
// 이보다 작은 감마 진폭(≈1.5/255)은 노이즈·그레인 바닥으로 보고 키우지 않습니다.
constexpr float sharpen_threshold = 0.006F;
constexpr float sharpen_halo = 0.10F;
// 부분 대비 창(가우시안 표준편차) = 긴 변의 0.6%. 분산 문턱(표준편차 0.1)과 헤일로 한도는
// GPU 판과 함께 쓰므로 `texture_stage.h` 에 있습니다.
constexpr float clarity_sigma_fraction = 0.006F;

[[nodiscard]] float encode(const float value) noexcept {
    return value <= 0.0031308F ? value * 12.92F
                               : 1.055F * std::pow(value, 1.0F / 2.4F) - 0.055F;
}

[[nodiscard]] float decode(const float value) noexcept {
    return value <= 0.04045F ? value / 12.92F
                             : std::pow((value + 0.055F) / 1.055F, 2.4F);
}

[[nodiscard]] float gamma_luma(const Rgb color) noexcept {
    return encode(clamp_unit(luminance(color)));
}

// 감마 휘도를 `lift` 만큼 옮긴 화소입니다. 원 휘도의 45% 와 ≈2/255 아래로는 내리지 않습니다
// (검정 붕괴·0 끝 빈 방지).
[[nodiscard]] Rgb with_lift(const Rgb color, const float luma, const float encoded, const float lift) noexcept {
    const float floor_value = std::max(encoded * 0.45F, std::min(encoded, 0.008F));
    const float target = std::max(encoded + lift, floor_value);
    return color * (decode(target) / luma);
}

// 단일 채널 평면의 분리형 가우시안(가장자리 복제, Core Image 유효 시그마)입니다. 축소 해상도
// 계수 평면에만 쓰므로 순차로 충분합니다.
[[nodiscard]] std::vector<float> blurred_plane(
    const std::vector<float>& plane,
    const std::uint32_t width,
    const std::uint32_t height,
    const float sigma) {
    const float effective = coreimage_gaussian_effective_sigma(sigma);
    const int radius = std::max(1, coreimage_gaussian_support_radius(sigma));
    std::vector<float> weights(static_cast<std::size_t>(radius * 2 + 1));
    float total = 0.0F;
    for (int offset = -radius; offset <= radius; ++offset) {
        const float weight = std::exp(-static_cast<float>(offset * offset) / (2.0F * effective * effective));
        weights[static_cast<std::size_t>(offset + radius)] = weight;
        total += weight;
    }
    for (float& weight : weights) {
        weight /= total;
    }
    std::vector<float> horizontal(plane.size());
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            float sum = 0.0F;
            for (int offset = -radius; offset <= radius; ++offset) {
                const int sx = std::clamp(static_cast<int>(x) + offset, 0, static_cast<int>(width) - 1);
                sum += weights[static_cast<std::size_t>(offset + radius)] *
                    plane[index_of(static_cast<std::uint32_t>(sx), y, width)];
            }
            horizontal[index_of(x, y, width)] = sum;
        }
    }
    std::vector<float> output(plane.size());
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            float sum = 0.0F;
            for (int offset = -radius; offset <= radius; ++offset) {
                const int sy = std::clamp(static_cast<int>(y) + offset, 0, static_cast<int>(height) - 1);
                sum += weights[static_cast<std::size_t>(offset + radius)] *
                    horizontal[index_of(x, static_cast<std::uint32_t>(sy), width)];
            }
            output[index_of(x, y, width)] = sum;
        }
    }
    return output;
}

// 축소 평면의 쌍선형 표본입니다. 원본 화소 중심 (x+0.5) 은 축소 좌표 (x+0.5)/factor 에 놓입니다.
[[nodiscard]] float bilinear(
    const std::vector<float>& plane,
    const std::uint32_t width,
    const std::uint32_t height,
    const float u,
    const float v) noexcept {
    const float cu = std::clamp(u, 0.0F, static_cast<float>(width - 1U));
    const float cv = std::clamp(v, 0.0F, static_cast<float>(height - 1U));
    const auto x0 = static_cast<std::uint32_t>(cu);
    const auto y0 = static_cast<std::uint32_t>(cv);
    const std::uint32_t x1 = std::min(x0 + 1U, width - 1U);
    const std::uint32_t y1 = std::min(y0 + 1U, height - 1U);
    const float fx = cu - static_cast<float>(x0);
    const float fy = cv - static_cast<float>(y0);
    const float top = plane[index_of(x0, y0, width)] * (1.0F - fx) + plane[index_of(x1, y0, width)] * fx;
    const float bottom = plane[index_of(x0, y1, width)] * (1.0F - fx) + plane[index_of(x1, y1, width)] * fx;
    return top * (1.0F - fy) + bottom * fy;
}

}  // namespace

void apply_detail_sharpen(
    WorkingImage& image,
    const float sharpness,
    std::size_t& scratch_peak_bytes) {
    const float long_side = static_cast<float>(std::max(image.width, image.height));
    const float sigma = std::max(0.5F, (0.7F + 0.5F * sharpness) * long_side / reference_long_side);
    const float amount = 1.6F * sharpness;
    gaussian_transform(
        image,
        sigma,
        GaussianEdgeMode::clamp,
        [](const negaflow::core::Rgba32F source) noexcept {
            const float value = gamma_luma(rgb(source));
            return FilterSample{Rgb{value, value, value}, source.alpha};
        },
        [amount](const negaflow::core::Rgba32F source, const FilterSample blurred) noexcept {
            const Rgb color = rgb(source);
            const float luma = luminance(color);
            if (luma <= 1.0e-5F) {
                return FilterSample{color, source.alpha};
            }
            const float encoded = encode(luma);
            const float detail = std::min(encoded, 1.0F) - blurred.color.red;
            const float cored = detail * (detail * detail /
                (detail * detail + sharpen_threshold * sharpen_threshold));
            const float lift = sharpen_halo * std::tanh(amount * cored / sharpen_halo);
            return FilterSample{with_lift(color, luma, encoded, lift), source.alpha};
        },
        scratch_peak_bytes);
}

void apply_local_contrast(WorkingImage& image, const float clarity) {
    const std::uint32_t width = image.width;
    const std::uint32_t height = image.height;
    const LocalContrastPlan plan = plan_local_contrast(width, height, clarity);
    const std::uint32_t factor = plan.factor;
    const std::uint32_t low_width = plan.low_width;
    const std::uint32_t low_height = plan.low_height;

    // 감마 휘도를 factor×factor 칸 평균으로 줄인 안내 평면입니다(He & Sun 2015 고속 가이디드 필터).
    // 칸마다 독립이라 행 묶음으로 나눠 돌려도 값이 같습니다(GPU 판은 칸마다 스레드 하나).
    std::vector<float> guide(checked_count(low_width, low_height), 0.0F);
    std::vector<float> squared(guide.size(), 0.0F);
    negaflow::core::for_each_row_block(
        low_height,
        static_cast<std::uint64_t>(width) * height,
        [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
            for (std::uint32_t ly = first_row; ly < first_row + row_count; ++ly) {
                for (std::uint32_t lx = 0U; lx < low_width; ++lx) {
                    float sum = 0.0F;
                    std::uint32_t count = 0U;
                    for (std::uint32_t y = ly * factor; y < std::min(height, (ly + 1U) * factor); ++y) {
                        const auto* row = image.pixels.data() + static_cast<std::size_t>(y) * image.stride_pixels;
                        for (std::uint32_t x = lx * factor; x < std::min(width, (lx + 1U) * factor); ++x) {
                            sum += gamma_luma(rgb(row[x]));
                            ++count;
                        }
                    }
                    const float mean = count > 0U ? sum / static_cast<float>(count) : 0.0F;
                    guide[index_of(lx, ly, low_width)] = mean;
                    squared[index_of(lx, ly, low_width)] = mean * mean;
                }
            }
        });
    const float low_sigma = plan.low_sigma;
    const std::vector<float> mean_guide = blurred_plane(guide, low_width, low_height, low_sigma);
    const std::vector<float> mean_squared = blurred_plane(squared, low_width, low_height, low_sigma);
    std::vector<float> a(guide.size());
    std::vector<float> b(guide.size());
    for (std::size_t index = 0U; index < guide.size(); ++index) {
        const float variance = std::max(mean_squared[index] - mean_guide[index] * mean_guide[index], 0.0F);
        a[index] = variance / (variance + local_contrast_epsilon);
        b[index] = mean_guide[index] - a[index] * mean_guide[index];
    }
    const std::vector<float> mean_a = blurred_plane(a, low_width, low_height, low_sigma);
    const std::vector<float> mean_b = blurred_plane(b, low_width, low_height, low_sigma);

    const float amount = plan.amount;
    const float inverse_factor = 1.0F / static_cast<float>(factor);
    const std::uint64_t work_units = static_cast<std::uint64_t>(width) * height;
    negaflow::core::for_each_row_block(
        height,
        work_units,
        [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
            for (std::uint32_t y = first_row; y < first_row + row_count; ++y) {
                auto* row = image.pixels.data() + static_cast<std::size_t>(y) * image.stride_pixels;
                const float v = (static_cast<float>(y) + 0.5F) * inverse_factor - 0.5F;
                for (std::uint32_t x = 0U; x < width; ++x) {
                    const Rgb color = rgb(row[x]);
                    const float luma = luminance(color);
                    if (luma <= 1.0e-5F) {
                        continue;
                    }
                    const float u = (static_cast<float>(x) + 0.5F) * inverse_factor - 0.5F;
                    const float coefficient_a = bilinear(mean_a, low_width, low_height, u, v);
                    const float coefficient_b = bilinear(mean_b, low_width, low_height, u, v);
                    const float encoded = encode(luma);
                    const float g = clamp_unit(encoded);
                    const float base = clamp_unit(coefficient_a * g + coefficient_b);
                    const float weight = clamp_unit(4.0F * g * (1.0F - g));
                    // a 는 그 자리가 경계인 정도입니다 — (1−a) 로 큰 경계 둘레(가이디드 필터 헤일로)를 걷어 냅니다.
                    const float texture = 1.0F - clamp_unit(coefficient_a);
                    const float lift = local_contrast_halo *
                        std::tanh(amount * weight * texture * (g - base) / local_contrast_halo);
                    const Rgb output = with_lift(color, luma, encoded, lift);
                    row[x].red = output.red;
                    row[x].green = output.green;
                    row[x].blue = output.blue;
                }
            }
        });
}

}  // namespace negaflow::imaging::texture_stage_detail

namespace negaflow::imaging {

LocalContrastPlan plan_local_contrast(
    const std::uint32_t width,
    const std::uint32_t height,
    const float clarity) noexcept {
    const float long_side = static_cast<float>(std::max(width, height));
    const float sigma = std::max(1.5F, texture_stage_detail::clarity_sigma_fraction * long_side);
    LocalContrastPlan plan{};
    plan.factor = static_cast<std::uint32_t>(std::max(1.0F, std::floor(sigma / 3.0F)));
    plan.low_width = (width + plan.factor - 1U) / plan.factor;
    plan.low_height = (height + plan.factor - 1U) / plan.factor;
    plan.low_sigma = sigma / static_cast<float>(plan.factor);
    plan.amount = clarity >= 0.0F ? 0.9F * clarity : 0.8F * clarity;
    return plan;
}

}  // namespace negaflow::imaging
