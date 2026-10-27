#include "negaflow/imaging/scene_correction.h"
#include "negaflow/core/negative_inversion.h"

#include "negaflow/core/parallel_rows.h"
#include "negaflow/imaging/neutral_axis_evidence.h"

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
    const negaflow::core::ConstImageView image,
    const std::uint32_t target_width,
    const std::uint32_t target_y,
    const double inverse_scale_x, const double inverse_scale_y,
    SceneSampleGrid& samples) noexcept {
    const double top = static_cast<double>(target_y) * inverse_scale_y;
    const double bottom = static_cast<double>(target_y + 1U) * inverse_scale_y;
    const std::uint32_t first_y = static_cast<std::uint32_t>(std::floor(top));
    const std::uint32_t last_y = std::min(
        image.height,
        static_cast<std::uint32_t>(std::ceil(bottom)));
    const std::size_t sample_row = static_cast<std::size_t>(target_y) * target_width;
    for (std::uint32_t target_x = 0U; target_x < target_width; ++target_x) {
        const double left = static_cast<double>(target_x) * inverse_scale_x;
        const double right = static_cast<double>(target_x + 1U) * inverse_scale_x;
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
    const negaflow::core::ConstImageView image,
    const std::uint32_t long_edge,
    SceneSampleGrid& samples) {
    std::uint32_t target_width = 0U, target_height = 0U;
    if (!scene_sample_grid_extent(image.width, image.height, long_edge, target_width, target_height)) {
        return false;
    }
    const std::size_t count =
        static_cast<std::size_t>(target_width) * target_height;
    // 예전에는 `push_back` 이라 목표 행을 순서대로 돌아야 했습니다. 자리를 미리 잡아 두면
    // 행마다 자기 칸에만 쓰므로 순서가 필요 없어지고, 담기는 값과 담기는 자리는 그대로입니다.
    samples.width = target_width; samples.height = target_height;
    samples.red.resize(count);
    samples.green.resize(count);
    samples.blue.resize(count);

    // `image.width / target_width` 로 줄이지 마십시오. 나눗셈 한 번과 두 번은 마지막
    // 비트가 다를 수 있고, 그러면 칸 경계가 한 화소 옮겨가 표본이 달라집니다.
    const double inverse_scale_x = static_cast<double>(image.width) / target_width;
    const double inverse_scale_y = static_cast<double>(image.height) / target_height;
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
                        image, target_width, target_y, inverse_scale_x, inverse_scale_y, samples)) {
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

// 표본을 모을 자리입니다 — 크롭 영역이 있으면 그 안, 없으면 전체 화상입니다. 호스트 화소가
// 최신일 때만 부릅니다(CPU 판은 호출부가 상주 화상을 먼저 내립니다).
[[nodiscard]] negaflow::core::ConstImageView measurement_view(
    const negaflow::core::ImageView image,
    const std::optional<AnalysisPixelRect>& rect) noexcept {
    const negaflow::core::ConstImageView full{
        image.pixels, image.pixel_capacity, image.width, image.height, image.stride_pixels};
    return rect ? analysis_subview(full, *rect) : full;
}

// 크롭이 없으면 프레임 가장자리를 버립니다. 크롭이면 경계는 이미 잘려 나갔습니다.
[[nodiscard]] bool collect_measured_samples(
    const negaflow::core::ImageView image,
    const std::optional<AnalysisRegion>& region,
    const std::uint32_t target_width,
    SceneSampleGrid& samples) {
    const std::optional<AnalysisPixelRect> rect =
        analysis_measurement_rect(region, image.width, image.height);
    if (!collect_area_samples(measurement_view(image, rect), target_width, samples)) {
        return false;
    }
    if (!rect) {
        inset_scene_samples(samples, samples.width, scene_frame_border_inset);
    }
    return true;
}

[[nodiscard]] bool apply_auto_levels(
    const negaflow::core::ImageView image,
    const bool negative_source,
    const bool linear_negative_output, const bool monochrome,
    const std::optional<AnalysisRegion>& region,
    SceneCorrectionInfo& info) {
    SceneSampleGrid samples{};
    if (!collect_measured_samples(image, region, scene_auto_levels_sample_width, samples)) {
        return false;
    }
    info.sampled_pixels += samples.red.size();
    const SceneAutoLevelsPlan plan = plan_scene_auto_levels(samples, negative_source, linear_negative_output, monochrome);
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
                    const double luminance=0.2126*pixel.red+0.7152*pixel.green+0.0722*pixel.blue;
                    const double mapped=std::clamp(luminance*plan.scale[0]+plan.bias[0],0.0,scene_auto_levels_upper_clamp);
                    if (luminance>1e-8) {
                        const double gain=mapped/luminance;
                        pixel.red=static_cast<float>(pixel.red*gain); pixel.green=static_cast<float>(pixel.green*gain);
                        pixel.blue=static_cast<float>(pixel.blue*gain);
                    } else { pixel.red=pixel.green=pixel.blue=static_cast<float>(std::max(plan.bias[0],0.0)); }
                }
            }
        });
    return true;
}

[[nodiscard]] float power_gain(
    const float value,
    const double exponent,
    const double gain) noexcept {
    return value > 0.0F
        ? static_cast<float>(gain * std::pow(static_cast<double>(value), exponent))
        : value;
}

[[nodiscard]] bool apply_neutral_balance(
    const negaflow::core::ImageView image,
    const std::optional<AnalysisRegion>& region,
    SceneCorrectionInfo& info) {
    if (image.width <= 8U || image.height <= 8U) {
        return false;
    }
    SceneSampleGrid samples{};
    if (!collect_measured_samples(image, region, scene_neutral_balance_sample_width, samples)) {
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
                    pixel.red = power_gain(pixel.red, plan.exponent[0], plan.gain[0]);
                    pixel.green = power_gain(pixel.green, plan.exponent[1], plan.gain[1]);
                    pixel.blue = power_gain(pixel.blue, plan.exponent[2], plan.gain[2]);
                }
            }
        });
    return true;
}

} // namespace

bool scene_sample_grid_extent(
    const std::uint32_t image_width, const std::uint32_t image_height,
    const std::uint32_t long_edge, std::uint32_t& out_width, std::uint32_t& out_height) noexcept {
    out_width=0; out_height=0;
    if (image_width <= 4 || image_height <= 4 || long_edge == 0 || long_edge > 512) { return false; }
    const double scale=std::min(1.0,static_cast<double>(long_edge)/std::max(image_width,image_height));
    out_width=std::max(1U,static_cast<std::uint32_t>(image_width*scale));
    out_height=std::max(1U,static_cast<std::uint32_t>(image_height*scale));
    return static_cast<std::uint64_t>(out_width)*out_height >= 64U;
}

SceneAutoLevelsPlan plan_scene_auto_levels(
    SceneSampleGrid& samples,
    const bool negative_source, const bool linear_negative_output, const bool monochrome) noexcept {
    SceneAutoLevelsPlan plan{};
    if (samples.red.empty() || samples.red.size() != samples.green.size() ||
        samples.red.size() != samples.blue.size()) {
        return plan;
    }
    std::vector<double> luminance;
    try {
        luminance.reserve(samples.red.size());
        for (std::size_t i = 0; i < samples.red.size(); ++i) {
            const double y = 0.2126 * samples.red[i] + 0.7152 * samples.green[i] + 0.0722 * samples.blue[i];
            if (std::isfinite(y)) { luminance.push_back(y); }
        }
    } catch (...) {
        return plan;
    }
    if (luminance.empty()) { return plan; }
    std::sort(luminance.begin(),luminance.end());
    const double black=percentile(luminance,negative_source?0.005:0.002);
    const double white=percentile(luminance,0.999);
    const double required_range=linear_negative_output?minimum_range*white:minimum_range;
    if (white<=1e-5 || white-black<required_range ||
        (!linear_negative_output && white>0.95 && white<1.05 && black<0.05)) { return plan; }
    const double output_black = negative_source
        ? (linear_negative_output ? core::negative_output_tone_input(negative_output_black, monochrome) : negative_output_black)
        : positive_output_black;
    const double output_white = negative_source
        ? (linear_negative_output ? core::negative_output_tone_input(negative_output_white, monochrome) : negative_output_white)
        : positive_output_white;
    for (std::size_t channel = 0U; channel < 3U; ++channel) {
        const double range = white - black;
        if (range >= required_range) {
            plan.scale[channel] = (output_white - output_black) / range;
            plan.bias[channel] =
                output_black - (black * plan.scale[channel]);
        }
    }
    plan.apply = true;
    return plan;
}

void inset_scene_samples(
    SceneSampleGrid& samples,
    const std::uint32_t grid_width,
    const double fraction) {
    const std::size_t count = samples.red.size();
    if (grid_width == 0U || count == 0U || count % grid_width != 0U ||
        samples.green.size() != count || samples.blue.size() != count) {
        return;
    }
    const std::uint32_t grid_height = static_cast<std::uint32_t>(count / grid_width);
    const std::uint32_t inset_x = static_cast<std::uint32_t>(static_cast<double>(grid_width) * fraction);
    const std::uint32_t inset_y = static_cast<std::uint32_t>(static_cast<double>(grid_height) * fraction);
    SceneSampleGrid kept{};
    kept.red.reserve(count);
    kept.green.reserve(count);
    kept.blue.reserve(count);
    const std::uint32_t last_y = std::max(inset_y + 1U, grid_height > inset_y ? grid_height - inset_y : 0U);
    const std::uint32_t last_x = std::max(inset_x + 1U, grid_width > inset_x ? grid_width - inset_x : 0U);
    for (std::uint32_t y = inset_y; y < last_y; ++y) {
        for (std::uint32_t x = inset_x; x < last_x; ++x) {
            const std::size_t index =
                (static_cast<std::size_t>(std::min(y, grid_height - 1U)) * grid_width) +
                std::min(x, grid_width - 1U);
            kept.red.push_back(samples.red[index]);
            kept.green.push_back(samples.green[index]);
            kept.blue.push_back(samples.blue[index]);
        }
    }
    kept.width=last_x-inset_x; kept.height=last_y-inset_y;
    samples = std::move(kept);
}

namespace {

// 한 채널 보정의 상한 — 게인 ±1 스톱(ln 0.7), 감마 0.8…1.25 입니다.
constexpr double maximum_offset = 0.7;
constexpr double minimum_slope = 0.8;
constexpr double maximum_slope = 1.25;
// 감마까지 맞추는 최소 근거: 대역 셋, 휘도 폭 2 스톱입니다.
constexpr std::size_t minimum_bands_for_slope = 3U;
const double minimum_span_for_slope = std::log(4.0);
// 이보다 작은 보정은 항등으로 봅니다.
constexpr double identity_tolerance = 0.003;

}  // namespace

namespace {
bool slope_improves_holdout(const std::vector<NeutralAxisBand>& bands) noexcept {
    if (bands.size()<4U) { return false; }
    double mx=0; std::array<double,3> my{}; std::size_t n=0;
    for (std::size_t i=0;i<bands.size();i+=2U) { mx+=bands[i].log_luminance; for(std::size_t c=0;c<3;++c) {my[c]+=bands[i].cast[c];} ++n; }
    mx/=static_cast<double>(n); for(auto& v:my){v/=static_cast<double>(n);}
    double sxx=0;std::array<double,3> sxy{},a{},b{};
    for(std::size_t i=0;i<bands.size();i+=2U){const double dx=bands[i].log_luminance-mx;sxx+=dx*dx;
        for(std::size_t c=0;c<3;++c){sxy[c]+=dx*(bands[i].cast[c]-my[c]);}}
    if(sxx<=1e-12){return false;}
    for(std::size_t c=0;c<3;++c){b[c]=sxy[c]/sxx;a[c]=my[c]-b[c]*mx;}
    double before=0,after=0;
    for(std::size_t i=1;i<bands.size();i+=2U){for(std::size_t c=0;c<3;++c){
        const double residual=bands[i].cast[c]-a[c]-b[c]*bands[i].log_luminance;
        before+=bands[i].cast[c]*bands[i].cast[c];after+=residual*residual;}}
    return before>1e-8 && after<before*0.8;
}
}

SceneNeutralBalancePlan plan_scene_neutral_balance(SceneSampleGrid& samples) noexcept {
    SceneNeutralBalancePlan plan{};
    if (samples.red.size() < 64U || samples.red.size() != samples.green.size() ||
        samples.red.size() != samples.blue.size()) {
        return plan;
    }
    try {
        std::vector<std::array<double, 3>> pixels;
        pixels.reserve(samples.red.size());
        for (std::size_t index = 0U; index < samples.red.size(); ++index) {
            pixels.push_back({samples.red[index], samples.green[index], samples.blue[index]});
        }
        const std::optional<NeutralAxisEvidence> evidence = measure_neutral_axis(pixels);
        if (!evidence) {
            return plan;
        }
        const double strength = evidence->confidence;
        // 대역 중앙 캐스트에 채널별 직선(cast = a + b·ln Ȳ)을 맞춥니다 — 대역마다 같은 무게.
        const auto& bands = evidence->bands;
        double minimum_x = bands.front().log_luminance;
        double maximum_x = bands.front().log_luminance;
        double mean_x = 0.0;
        for (const NeutralAxisBand& band : bands) {
            minimum_x = std::min(minimum_x, band.log_luminance);
            maximum_x = std::max(maximum_x, band.log_luminance);
            mean_x += band.log_luminance;
        }
        const double n = static_cast<double>(bands.size());
        mean_x /= n;
        const bool use_slope =
            bands.size() >= minimum_bands_for_slope && maximum_x - minimum_x >= minimum_span_for_slope &&
            slope_improves_holdout(bands);
        bool identity = true;
        for (std::size_t channel = 0U; channel < 3U; ++channel) {
            double mean_y = 0.0;
            for (const NeutralAxisBand& band : bands) {
                mean_y += band.cast[channel];
            }
            mean_y /= n;
            double slope = 0.0;
            if (use_slope) {
                double sxy = 0.0;
                double sxx = 0.0;
                for (const NeutralAxisBand& band : bands) {
                    sxy += (band.log_luminance - mean_x) * (band.cast[channel] - mean_y);
                    sxx += (band.log_luminance - mean_x) * (band.log_luminance - mean_x);
                }
                slope = sxx > 1.0e-12 ? sxy / sxx : 0.0;
            }
            const double intercept = use_slope ? mean_y - (slope * mean_x) : mean_y;
            const double offset = std::clamp(intercept * strength, -maximum_offset, maximum_offset);
            const double beta = std::clamp(1.0 + (slope * strength), minimum_slope, maximum_slope);
            identity = identity && std::abs(offset) < identity_tolerance &&
                       std::abs(beta - 1.0) < identity_tolerance;
            // c' = exp((ln c − α)/β) = exp(−α/β) · c^(1/β)
            plan.exponent[channel] = 1.0 / beta;
            plan.gain[channel] = std::exp(-offset * plan.exponent[channel]);
        }
        if (identity) {
            return SceneNeutralBalancePlan{};
        }
        plan.apply = true;
        return plan;
    } catch (...) {
        return SceneNeutralBalancePlan{};
    }
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
            info.auto_levels_applied = apply_auto_levels(
                image, parameters.negative_source, parameters.linear_negative_output, parameters.monochrome, parameters.analysis_region, info);
        }
        if (parameters.auto_neutral_balance && parameters.negative_source) {
            info.neutral_balance_applied =
                apply_neutral_balance(image, parameters.analysis_region, info);
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
