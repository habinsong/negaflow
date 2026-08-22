#include "negaflow/imaging/scene_correction.h"

#include "negaflow/core/parallel_rows.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstddef>
#include <limits>
#include <new>
#include <vector>

namespace negaflow::imaging {
namespace {

constexpr double minimum_range = 0.04;
constexpr double negative_output_black = 0.003;
constexpr double negative_output_white = 0.95;
constexpr double positive_output_black = 0.014;
constexpr double positive_output_white = 0.86;

[[nodiscard]] double overlap(
    const double a0,
    const double a1,
    const double b0,
    const double b1) noexcept {
    return std::max(0.0, std::min(a1, b1) - std::max(a0, b0));
}

// 목표 격자 한 행입니다. 원본에서 겹치는 만큼 가중 평균해 자기 칸에만 씁니다 —
// 다른 행과 겹치는 자리가 없으므로 행끼리 순서가 필요 없습니다.
[[nodiscard]] bool collect_sample_row(
    const negaflow::core::ImageView image,
    const std::uint32_t target_width,
    const std::uint32_t target_y,
    const double inverse_scale,
    SceneSampleGrid& samples) noexcept {
    const double top = static_cast<double>(target_y) * inverse_scale;
    const double bottom = static_cast<double>(target_y + 1U) * inverse_scale;
    const std::uint32_t first_y = static_cast<std::uint32_t>(std::floor(top));
    const std::uint32_t last_y = std::min(
        image.height,
        static_cast<std::uint32_t>(std::ceil(bottom)));
    const std::size_t sample_row = static_cast<std::size_t>(target_y) * target_width;
    for (std::uint32_t target_x = 0U; target_x < target_width; ++target_x) {
        const double left = static_cast<double>(target_x) * inverse_scale;
        const double right = static_cast<double>(target_x + 1U) * inverse_scale;
        const std::uint32_t first_x = static_cast<std::uint32_t>(std::floor(left));
        const std::uint32_t last_x = std::min(
            image.width,
            static_cast<std::uint32_t>(std::ceil(right)));
        std::array<double, 3> sum{};
        double weight_sum = 0.0;
        for (std::uint32_t y = first_y; y < last_y; ++y) {
            const double y_weight = overlap(
                top, bottom, static_cast<double>(y), static_cast<double>(y + 1U));
            const std::size_t row = static_cast<std::size_t>(y) * image.stride_pixels;
            for (std::uint32_t x = first_x; x < last_x; ++x) {
                const double weight = y_weight * overlap(
                    left, right, static_cast<double>(x), static_cast<double>(x + 1U));
                const negaflow::core::Rgba32F pixel = image.pixels[row + x];
                sum[0] += static_cast<double>(pixel.red) * weight;
                sum[1] += static_cast<double>(pixel.green) * weight;
                sum[2] += static_cast<double>(pixel.blue) * weight;
                weight_sum += weight;
            }
        }
        if (weight_sum <= 0.0) {
            return false;
        }
        const std::size_t slot = sample_row + target_x;
        samples.red[slot] = sum[0] / weight_sum;
        samples.green[slot] = sum[1] / weight_sum;
        samples.blue[slot] = sum[2] / weight_sum;
    }
    return true;
}

[[nodiscard]] bool collect_area_samples(
    const negaflow::core::ImageView image,
    const std::uint32_t target_width,
    SceneSampleGrid& samples) {
    std::uint32_t target_height = 0U;
    if (!scene_sample_grid_extent(image.width, image.height, target_width, target_height)) {
        return false;
    }
    const std::size_t count =
        static_cast<std::size_t>(target_width) * target_height;
    // 예전에는 `push_back` 이라 목표 행을 순서대로 돌아야 했습니다. 자리를 미리 잡아 두면
    // 행마다 자기 칸에만 쓰므로 순서가 필요 없어지고, 담기는 값과 담기는 자리는 그대로입니다.
    samples.red.resize(count);
    samples.green.resize(count);
    samples.blue.resize(count);

    // `image.width / target_width` 로 줄이지 마십시오. 나눗셈 한 번과 두 번은 마지막
    // 비트가 다를 수 있고, 그러면 칸 경계가 한 화소 옮겨가 표본이 달라집니다.
    const double scale =
        static_cast<double>(target_width) / static_cast<double>(image.width);
    const double inverse_scale = 1.0 / scale;
    // 목표 행 하나가 원본을 (1/scale)^2 배로 읽습니다. work_units 에 그 배율을 넣지 않으면
    // 문턱을 못 넘어 조용히 직렬로 돕니다(`parallel_rows.h` 경고).
    std::atomic<bool> degenerate{false};
    negaflow::core::for_each_row_block(
        target_height,
        static_cast<std::uint64_t>(image.width) * image.height *
            sizeof(negaflow::core::Rgba32F),
        [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
            for (std::uint32_t target_y = first_row;
                 target_y < first_row + row_count;
                 ++target_y) {
                if (!collect_sample_row(
                        image, target_width, target_y, inverse_scale, samples)) {
                    degenerate.store(true, std::memory_order_relaxed);
                    return;
                }
            }
        });
    return !degenerate.load(std::memory_order_relaxed);
}

[[nodiscard]] double percentile(
    const std::vector<double>& values,
    const double fraction) noexcept {
    const std::size_t index = std::min(
        values.size() - 1U,
        static_cast<std::size_t>(static_cast<double>(values.size()) * fraction));
    return values[index];
}

[[nodiscard]] float cube_curve(
    const float value,
    const double (&table)[scene_cube_dimension]) noexcept {
    const double position = static_cast<double>(std::clamp(value, 0.0F, 1.0F)) *
                            static_cast<double>(scene_cube_dimension - 1U);
    const std::size_t lower = static_cast<std::size_t>(position);
    const std::size_t upper = std::min(scene_cube_dimension - 1U, lower + 1U);
    const double t = position - static_cast<double>(lower);
    const double a = table[lower];
    const double b = table[upper];
    return static_cast<float>(a + ((b - a) * t));
}

[[nodiscard]] bool apply_auto_levels(
    const negaflow::core::ImageView image,
    const bool negative_source,
    SceneCorrectionInfo& info) {
    SceneSampleGrid samples{};
    if (!collect_area_samples(image, scene_auto_levels_sample_width, samples)) {
        return false;
    }
    info.sampled_pixels += samples.red.size();
    const SceneAutoLevelsPlan plan = plan_scene_auto_levels(samples, negative_source);
    if (!plan.apply) {
        return false;
    }
    // 행끼리 완전히 독립입니다 — 각 화소는 자기 자리만 읽고 씁니다. 화소당 계산은 그대로
    // 두고 행 블록으로만 나눕니다. work_units 는 읽고 쓰는 바이트입니다(헤더 경고 참고).
    negaflow::core::for_each_row_block(
        image.height,
        static_cast<std::uint64_t>(image.width) * image.height *
            sizeof(negaflow::core::Rgba32F) * 2U,
        [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
            for (std::uint32_t y = first_row; y < first_row + row_count; ++y) {
                const std::size_t row = static_cast<std::size_t>(y) * image.stride_pixels;
                for (std::uint32_t x = 0U; x < image.width; ++x) {
                    negaflow::core::Rgba32F& pixel = image.pixels[row + x];
                    pixel.red = static_cast<float>(std::clamp(
                        (static_cast<double>(pixel.red) * plan.scale[0]) + plan.bias[0],
                        0.0, 1.0));
                    pixel.green = static_cast<float>(std::clamp(
                        (static_cast<double>(pixel.green) * plan.scale[1]) + plan.bias[1],
                        0.0, 1.0));
                    pixel.blue = static_cast<float>(std::clamp(
                        (static_cast<double>(pixel.blue) * plan.scale[2]) + plan.bias[2],
                        0.0, 1.0));
                }
            }
        });
    return true;
}

[[nodiscard]] bool apply_neutral_balance(
    const negaflow::core::ImageView image,
    SceneCorrectionInfo& info) {
    if (image.width <= 8U || image.height <= 8U) {
        return false;
    }
    SceneSampleGrid samples{};
    if (!collect_area_samples(image, scene_neutral_balance_sample_width, samples)) {
        return false;
    }
    info.sampled_pixels += samples.red.size();
    const SceneNeutralBalancePlan plan = plan_scene_neutral_balance(samples);
    if (!plan.apply) {
        return false;
    }
    negaflow::core::for_each_row_block(
        image.height,
        static_cast<std::uint64_t>(image.width) * image.height *
            sizeof(negaflow::core::Rgba32F) * 2U,
        [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
            for (std::uint32_t y = first_row; y < first_row + row_count; ++y) {
                const std::size_t row = static_cast<std::size_t>(y) * image.stride_pixels;
                for (std::uint32_t x = 0U; x < image.width; ++x) {
                    negaflow::core::Rgba32F& pixel = image.pixels[row + x];
                    pixel.red = cube_curve(pixel.red, plan.cube[0]);
                    pixel.green = cube_curve(pixel.green, plan.cube[1]);
                    pixel.blue = cube_curve(pixel.blue, plan.cube[2]);
                }
            }
        });
    return true;
}

} // namespace

bool scene_sample_grid_extent(
    const std::uint32_t image_width,
    const std::uint32_t image_height,
    const std::uint32_t target_width,
    std::uint32_t& out_height) noexcept {
    out_height = 0U;
    if (image_width <= 4U || image_height <= 4U || target_width == 0U) {
        return false;
    }
    const double scale =
        static_cast<double>(target_width) / static_cast<double>(image_width);
    const double scaled_height = std::floor(static_cast<double>(image_height) * scale);
    if (!std::isfinite(scaled_height) || scaled_height < 1.0 || scaled_height > 65536.0) {
        return false;
    }
    const std::uint32_t target_height = static_cast<std::uint32_t>(scaled_height);
    const std::uint64_t count64 =
        static_cast<std::uint64_t>(target_width) * target_height;
    if (count64 < 64U || count64 > 16U * 1024U * 1024U ||
        count64 > std::numeric_limits<std::size_t>::max()) {
        return false;
    }
    out_height = target_height;
    return true;
}

SceneAutoLevelsPlan plan_scene_auto_levels(
    SceneSampleGrid& samples,
    const bool negative_source) noexcept {
    SceneAutoLevelsPlan plan{};
    if (samples.red.empty() || samples.red.size() != samples.green.size() ||
        samples.red.size() != samples.blue.size()) {
        return plan;
    }
    std::sort(samples.red.begin(), samples.red.end());
    std::sort(samples.green.begin(), samples.green.end());
    std::sort(samples.blue.begin(), samples.blue.end());

    const double black_clip = negative_source ? 0.005 : 0.002;
    const std::array<double, 3> black{
        percentile(samples.red, black_clip),
        percentile(samples.green, black_clip),
        percentile(samples.blue, black_clip),
    };
    const std::array<double, 3> white{
        percentile(samples.red, 0.999),
        percentile(samples.green, 0.999),
        percentile(samples.blue, 0.999),
    };
    const double maximum_range = std::max({
        white[0] - black[0], white[1] - black[1], white[2] - black[2]});
    if (maximum_range < minimum_range ||
        (white[0] > 0.95 && white[1] > 0.95 && white[2] > 0.95 &&
         black[0] < 0.05 && black[1] < 0.05 && black[2] < 0.05)) {
        return plan;
    }

    const double output_black = negative_source
        ? negative_output_black
        : positive_output_black;
    const double output_white = negative_source
        ? negative_output_white
        : positive_output_white;
    for (std::size_t channel = 0U; channel < 3U; ++channel) {
        const double range = white[channel] - black[channel];
        if (range >= minimum_range) {
            plan.scale[channel] = (output_white - output_black) / range;
            plan.bias[channel] =
                output_black - (black[channel] * plan.scale[channel]);
        }
    }
    plan.apply = true;
    return plan;
}

SceneNeutralBalancePlan plan_scene_neutral_balance(SceneSampleGrid& samples) noexcept {
    SceneNeutralBalancePlan plan{};
    if (samples.red.empty() || samples.red.size() != samples.green.size() ||
        samples.red.size() != samples.blue.size()) {
        return plan;
    }
    std::sort(samples.red.begin(), samples.red.end());
    std::sort(samples.green.begin(), samples.green.end());
    std::sort(samples.blue.begin(), samples.blue.end());

    const std::size_t middle = samples.red.size() / 2U;
    const std::array<double, 3> median{
        samples.red[middle], samples.green[middle], samples.blue[middle]};
    for (const double value : median) {
        if (value <= 0.04 || value >= 0.96) {
            return plan;
        }
    }
    const double target = std::pow(median[0] * median[1] * median[2], 1.0 / 3.0);
    for (std::size_t channel = 0U; channel < 3U; ++channel) {
        const double raw = std::log(target) / std::log(median[channel]);
        plan.gamma[channel] = std::clamp(1.0 + ((raw - 1.0) * 0.8), 0.80, 1.25);
    }
    if (std::abs(plan.gamma[0] - 1.0) <= 0.01 &&
        std::abs(plan.gamma[1] - 1.0) <= 0.01 &&
        std::abs(plan.gamma[2] - 1.0) <= 0.01) {
        plan.gamma[0] = 1.0;
        plan.gamma[1] = 1.0;
        plan.gamma[2] = 1.0;
        return plan;
    }
    // 큐브 항목은 **칸 번호와 gamma 로만** 정해집니다. 그런데 예전 `cube_curve` 는
    // 화소마다 그 두 항목을 `std::pow` 로 다시 구했습니다 — 1536x1026 한 장이면
    // 채널마다 315만 번, 세 채널이면 946만 번입니다. 실측으로 이 루프 하나가 슬라이더
    // 한 틱 200ms 중 105ms 였습니다(3600 정착 패스에서는 618ms).
    //
    // **화소 값은 그대로입니다.** 같은 `std::pow` 에 같은 인자를 넣어 나온 같은 double 을
    // 표에 담아 두고 꺼내 쓸 뿐이며, 보간식과 float 축소도 그대로입니다.
    for (std::size_t channel = 0U; channel < 3U; ++channel) {
        for (std::size_t index = 0U; index < scene_cube_dimension; ++index) {
            plan.cube[channel][index] = std::pow(
                static_cast<double>(index) /
                    static_cast<double>(scene_cube_dimension - 1U),
                plan.gamma[channel]);
        }
    }
    plan.apply = true;
    return plan;
}

negaflow::core::KernelStatus apply_scene_correction(
    const negaflow::core::ImageView image,
    const SceneCorrectionParameters& parameters,
    SceneCorrectionInfo& info) noexcept {
    info = {};
    const negaflow::core::KernelStatus view_status =
        negaflow::core::validate_image_view(image);
    if (view_status != negaflow::core::KernelStatus::ok) {
        return view_status;
    }
    const negaflow::core::KernelStatus input_status =
        negaflow::core::validate_finite_pixels({
            image.pixels, image.pixel_capacity, image.width, image.height,
            image.stride_pixels});
    if (input_status != negaflow::core::KernelStatus::ok) {
        return input_status;
    }
    try {
        if (parameters.auto_levels) {
            info.auto_levels_applied =
                apply_auto_levels(image, parameters.negative_source, info);
        }
        if (parameters.auto_neutral_balance && parameters.negative_source) {
            info.neutral_balance_applied = apply_neutral_balance(image, info);
        }
    } catch (const std::bad_alloc&) {
        return negaflow::core::KernelStatus::buffer_too_small;
    } catch (...) {
        return negaflow::core::KernelStatus::invalid_argument;
    }
    return negaflow::core::validate_finite_pixels({
        image.pixels, image.pixel_capacity, image.width, image.height,
        image.stride_pixels});
}

} // namespace negaflow::imaging
