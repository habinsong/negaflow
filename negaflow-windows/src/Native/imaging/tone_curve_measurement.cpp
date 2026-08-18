#include "negaflow/imaging/tone_curve_measurement.h"

#include "negaflow/core/parallel_rows.h"

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cmath>
#include <limits>
#include <new>
#include <vector>

namespace negaflow::imaging {
namespace {

constexpr std::uint32_t minimum_target_width = 64U;
constexpr std::uint32_t maximum_target_width = 256U;
constexpr double border_fraction = 0.04;
constexpr std::uint64_t minimum_luma_samples = 64U;

void set_fallback(ToneCurveMeasurementResult& result) noexcept {
    result.status = ToneCurveMeasurementStatus::ok;
    result.kernel_status = negaflow::core::KernelStatus::ok;
    result.info.bands = fallback_parametric_tone_curve_bands();
    result.info.sampling_mode = ToneCurveSamplingMode::fixed_fallback;
    result.info.sampled_luma_count = 0U;
    result.info.peak_temporary_bytes = 0U;
}

[[nodiscard]] double interval_overlap(
    const double left_a,
    const double right_a,
    const double left_b,
    const double right_b) noexcept {
    return std::max(0.0, std::min(right_a, right_b) - std::max(left_a, left_b));
}

[[nodiscard]] double sampled_luma(
    const negaflow::core::ConstImageView image,
    const std::uint32_t target_x,
    const std::uint32_t target_y,
    const double inverse_scale) noexcept {
    const double source_left = static_cast<double>(target_x) * inverse_scale;
    const double source_right = static_cast<double>(target_x + 1U) * inverse_scale;
    const double source_top = static_cast<double>(target_y) * inverse_scale;
    const double source_bottom = static_cast<double>(target_y + 1U) * inverse_scale;

    const std::uint32_t first_x = static_cast<std::uint32_t>(std::floor(source_left));
    const std::uint32_t last_x = std::min(
        image.width,
        static_cast<std::uint32_t>(std::ceil(source_right)));
    const std::uint32_t first_y = static_cast<std::uint32_t>(std::floor(source_top));
    const std::uint32_t last_y = std::min(
        image.height,
        static_cast<std::uint32_t>(std::ceil(source_bottom)));

    double red_sum = 0.0;
    double green_sum = 0.0;
    double blue_sum = 0.0;
    double weight_sum = 0.0;
    for (std::uint32_t source_y = first_y; source_y < last_y; ++source_y) {
        const double y_weight = interval_overlap(
            source_top,
            source_bottom,
            static_cast<double>(source_y),
            static_cast<double>(source_y + 1U));
        const std::size_t row_offset =
            static_cast<std::size_t>(source_y) * image.stride_pixels;
        for (std::uint32_t source_x = first_x; source_x < last_x; ++source_x) {
            const double x_weight = interval_overlap(
                source_left,
                source_right,
                static_cast<double>(source_x),
                static_cast<double>(source_x + 1U));
            const double weight = x_weight * y_weight;
            const negaflow::core::Rgba32F source = image.pixels[row_offset + source_x];
            red_sum += static_cast<double>(source.red) * weight;
            green_sum += static_cast<double>(source.green) * weight;
            blue_sum += static_cast<double>(source.blue) * weight;
            weight_sum += weight;
        }
    }

    if (weight_sum <= 0.0) {
        return 0.0;
    }
    const float red = static_cast<float>(red_sum / weight_sum);
    const float green = static_cast<float>(green_sum / weight_sum);
    const float blue = static_cast<float>(blue_sum / weight_sum);
    return (static_cast<double>(red) * 0.2126) +
           (static_cast<double>(green) * 0.7152) +
           (static_cast<double>(blue) * 0.0722);
}

[[nodiscard]] double percentile(
    const std::vector<double>& sorted_luma,
    const double fraction) noexcept {
    const double position =
        static_cast<double>(sorted_luma.size() - 1U) * fraction;
    const std::size_t index = static_cast<std::size_t>(position);
    return std::clamp(sorted_luma[index], 0.0, 1.0);
}

[[nodiscard]] ParametricToneCurveBands derive_bands(
    const std::vector<double>& sorted_luma) noexcept {
    const double p10 = percentile(sorted_luma, 0.10);
    const double p35 = std::max(percentile(sorted_luma, 0.35), p10 + 0.025);
    const double p65 = std::max(percentile(sorted_luma, 0.65), p35 + 0.025);
    const double p90 = std::max(percentile(sorted_luma, 0.90), p65 + 0.025);
    return {
        static_cast<float>(std::max(0.0, p10 - 0.020)),
        static_cast<float>(p35),
        static_cast<float>(p35),
        static_cast<float>(p65),
        static_cast<float>(p65),
        static_cast<float>(p90),
        static_cast<float>(p65),
        static_cast<float>(std::min(1.0, p90 + 0.030)),
    };
}

}  // namespace

ToneCurveMeasurementResult measure_parametric_tone_curve_bands(
    const negaflow::core::ConstImageView image,
    const ToneCurveMeasurementLimits& limits,
    const bool pixels_already_finite) noexcept {
    ToneCurveMeasurementResult result{};
    // 레이아웃은 언제나 봅니다. 화소 유한성만 호출부가 이미 증명했으면 건너뜁니다 —
    // 그 확인은 전 화소를 한 번 더 훑고, 실측에서 톤 단계 비용의 큰 몫이었습니다.
    result.kernel_status = pixels_already_finite
        ? negaflow::core::validate_image_view(image)
        : negaflow::core::validate_finite_pixels(image);
    if (result.kernel_status != negaflow::core::KernelStatus::ok) {
        result.status = ToneCurveMeasurementStatus::invalid_input;
        return result;
    }

    if (image.width <= 8U || image.height <= 8U) {
        set_fallback(result);
        return result;
    }

    result.info.target_width = std::max(
        minimum_target_width,
        std::min(maximum_target_width, image.width));
    const double scale = static_cast<double>(result.info.target_width) /
                         static_cast<double>(image.width);
    const double scaled_height =
        std::floor(static_cast<double>(image.height) * scale);
    if (!std::isfinite(scaled_height) ||
        scaled_height > static_cast<double>(std::numeric_limits<std::uint32_t>::max())) {
        result.status = ToneCurveMeasurementStatus::sample_limit_exceeded;
        return result;
    }
    result.info.target_height = static_cast<std::uint32_t>(std::max(1.0, scaled_height));

    const std::uint64_t target_pixel_count =
        static_cast<std::uint64_t>(result.info.target_width) * result.info.target_height;
    if (target_pixel_count > limits.max_sample_pixels ||
        target_pixel_count > std::numeric_limits<std::size_t>::max() / sizeof(double)) {
        result.status = ToneCurveMeasurementStatus::sample_limit_exceeded;
        return result;
    }

    const std::uint32_t inset_x = std::max(
        1U,
        static_cast<std::uint32_t>(
            static_cast<double>(result.info.target_width) * border_fraction));
    const std::uint32_t inset_y = std::max(
        1U,
        static_cast<std::uint32_t>(
            static_cast<double>(result.info.target_height) * border_fraction));
    if (inset_x >= result.info.target_width || inset_y >= result.info.target_height) {
        set_fallback(result);
        return result;
    }
    const std::uint32_t end_x = std::max(
        inset_x + 1U,
        result.info.target_width - inset_x);
    const std::uint32_t end_y = std::max(
        inset_y + 1U,
        result.info.target_height - inset_y);
    const std::uint64_t interior_count =
        static_cast<std::uint64_t>(end_x - inset_x) * (end_y - inset_y);
    if (interior_count < minimum_luma_samples) {
        set_fallback(result);
        return result;
    }

    try {
        // ☠️ 이 표본 추출은 **GPU 로 옮길 수 없습니다.** `sampled_luma` 가 가중치와 누적을
        //    `double` 로 하는데 D3D11 의 double 은 **선택 기능**이라 벤더에 따라 없습니다
        //    (`docs/audit/13-performance-playbook.md` 18절). float 로 낮추면 백분위가 달라지고
        //    밴드가 달라져 **출력 화소가 달라집니다.**
        //
        // ☠️ **`work_units` 에 표본 격자 크기를 넘기면 안 됩니다.**
        //    격자는 236×162 = 38,232 밖에 안 되는데 `run_row_blocks` 는
        //    100만(`minimum_parallel_row_work_units`) 미만이면 **쪼개지 않고 통째로 직렬 실행**합니다.
        //    격자 크기를 넘기면 병렬화가 **조용히 꺼진 채** 돕니다 — 경고도 실패도 없습니다.
        //
        //    표본 하나가 원본에서 `inverse_scale` 변의 정사각형을 읽으므로, 진짜 작업량은
        //    격자 × `ceil(inverse_scale)²` 입니다. 5100 폭이면 38,232 × 400 ≈ **1,686만**.
        //
        //    ☠️ 앞서 두 번 "병렬화해도 이득이 없다" 고 적었던 것은 **이 문턱에 걸려
        //       스레드가 하나도 안 뜬 상태를 잰 것**이었습니다. 그리고 그 결과에
        //       "메모리 대역폭에 묶였다" 는, **재지 않은 설명**을 붙였습니다.
        //       실제로는 이 루프만 떼어 재면 **32.0 ms → 5.0 ms (6.4배)** 입니다
        //       (`docs/audit/13-performance-playbook.md` 21절).
        //
        // 결과는 직렬과 **비트 단위로 같습니다** — 표본끼리 독립이고, 각 블록이 자기 행의
        // 자리에만 적으며, 뒤에서 어차피 정렬합니다.
        std::vector<double> luma_values(static_cast<std::size_t>(interior_count));
        const double inverse_scale = 1.0 / scale;
        const std::uint32_t column_span = end_x - inset_x;
        const std::uint32_t row_span = end_y - inset_y;
        const std::uint64_t source_pixels_per_sample = static_cast<std::uint64_t>(
            std::max(1.0, std::ceil(inverse_scale) * std::ceil(inverse_scale)));
#if defined(NEGA_SAMPLE_TRACE)
        const auto trace_started = std::chrono::steady_clock::now();
#endif
        negaflow::core::for_each_row_block(
            row_span,
            interior_count * source_pixels_per_sample,
            [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
                for (std::uint32_t row = first_row; row < first_row + row_count; ++row) {
                    double* const destination =
                        luma_values.data() + (static_cast<std::size_t>(row) * column_span);
                    const std::uint32_t target_y = inset_y + row;
                    for (std::uint32_t column = 0U; column < column_span; ++column) {
                        destination[column] = sampled_luma(
                            image,
                            inset_x + column,
                            target_y,
                            inverse_scale);
                    }
                }
            });
#if defined(NEGA_SAMPLE_TRACE)
        const auto trace_sampled = std::chrono::steady_clock::now();
#endif
        std::sort(luma_values.begin(), luma_values.end());
#if defined(NEGA_SAMPLE_TRACE)
        const auto trace_sorted = std::chrono::steady_clock::now();
        std::fprintf(
            stderr,
            "[bandsample] grid=%ux%u source_reads=%llu sample_us=%lld sort_us=%lld\n",
            column_span,
            row_span,
            static_cast<unsigned long long>(interior_count * source_pixels_per_sample),
            static_cast<long long>(std::chrono::duration_cast<std::chrono::microseconds>(
                                       trace_sampled - trace_started)
                                       .count()),
            static_cast<long long>(std::chrono::duration_cast<std::chrono::microseconds>(
                                       trace_sorted - trace_sampled)
                                       .count()));
#endif
        result.info.bands = derive_bands(luma_values);
        result.info.sampling_mode = ToneCurveSamplingMode::portable_area_v1;
        result.info.sampled_luma_count = luma_values.size();
        result.info.peak_temporary_bytes =
            static_cast<std::uint64_t>(luma_values.size()) * sizeof(double);
        result.status = ToneCurveMeasurementStatus::ok;
        result.kernel_status = negaflow::core::KernelStatus::ok;
        return result;
    } catch (const std::bad_alloc&) {
        result.status = ToneCurveMeasurementStatus::allocation_failed;
        return result;
    } catch (...) {
        result.status = ToneCurveMeasurementStatus::invalid_input;
        return result;
    }
}

const char* tone_curve_sampling_mode_name(const ToneCurveSamplingMode mode) noexcept {
    switch (mode) {
        case ToneCurveSamplingMode::none:
            return "none";
        case ToneCurveSamplingMode::fixed_fallback:
            return "fixed_fallback";
        case ToneCurveSamplingMode::portable_area_v1:
            return "portable_area_v1";
    }
    return "unknown";
}

const char* tone_curve_measurement_status_name(
    const ToneCurveMeasurementStatus status) noexcept {
    switch (status) {
        case ToneCurveMeasurementStatus::ok:
            return "ok";
        case ToneCurveMeasurementStatus::invalid_input:
            return "invalid_input";
        case ToneCurveMeasurementStatus::sample_limit_exceeded:
            return "sample_limit_exceeded";
        case ToneCurveMeasurementStatus::allocation_failed:
            return "allocation_failed";
    }
    return "unknown";
}

}  // namespace negaflow::imaging
