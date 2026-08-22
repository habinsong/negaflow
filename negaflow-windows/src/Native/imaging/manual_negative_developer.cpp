#include "negaflow/imaging/manual_negative_developer.h"

#include "negaflow/imaging/kernel_accelerator.h"

#include "negaflow/imaging/mipmap_downsampler.h"

#include "bilinear_rgb_sampler.h"
#include "negaflow/core/negative_inversion.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdio>
#include <cstdlib>
#include <optional>
#include <utility>
#include <vector>

namespace negaflow::imaging {
namespace {

// macOS 가 NEGA_DEBUG 로 내보내는 것과 **같은 줄**을 같은 이름·같은 자릿수로 씁니다. 두
// 구현을 나란히 놓고 견주는 것이 이 진단의 유일한 용도이므로 서식이 갈리면 쓸모가 없습니다.
[[nodiscard]] bool debug_enabled() noexcept {
    std::size_t length = 0U;
    return getenv_s(&length, nullptr, 0U, "NEGA_DEBUG") == 0 && length > 0U;
}

void discard_pixels(WorkingImage& image) noexcept {
    std::vector<negaflow::core::Rgba32F>{}.swap(image.pixels);
}

[[nodiscard]] bool has_compatible_layout(const WorkingImage& image) noexcept {
    if (image.width <= 8U || image.height <= 8U || image.stride_pixels < image.width) {
        return false;
    }
    const std::size_t required =
        static_cast<std::size_t>(image.stride_pixels) * image.height;
    return required / image.height == image.stride_pixels && image.pixels.size() >= required;
}

[[nodiscard]] float percentile(
    const std::vector<float>& sorted,
    const double fraction) noexcept {
    const std::size_t index = std::min(
        sorted.size() - 1U,
        static_cast<std::size_t>(static_cast<double>(sorted.size() - 1U) * fraction));
    return sorted[index];
}

[[nodiscard]] std::optional<std::array<float, 3>> scene_density_range(
    const WorkingImage& image,
    const std::array<float, 3>& dmin,
    const negaflow::core::PrintResponse& response,
    const NegativeFilmType film_type,
    std::array<float, 3>* out_black_input = nullptr) noexcept {
    if (!has_compatible_layout(image)) {
        return std::nullopt;
    }

    // This mirrors the macOS sampleStats geometry and affine sampling: a 64...320-wide
    // uniform-scale linear proxy, pixel-centre bilinear sampling, and a 6% frame inset.
    // The bounded sample count keeps a panoramic source from turning a statistic into a
    // second full-frame allocation.
    constexpr std::uint32_t maximum_sample_width = 320U;
    constexpr std::uint32_t minimum_sample_width = 64U;
    // macOS bounds only the width; the height follows the aspect ratio with no cap. The
    // guard here exists so a 1:10 panorama cannot turn a statistic into a second
    // full-frame allocation -- but at 320 x 480 it also fired on ordinary film frames
    // slightly taller than 2:3 (a 2272 x 3471 scan wants 320 x 488), shrinking the grid
    // to 317 x 484 and measuring a different percentile than macOS. Admit anything up to
    // a 1:4 frame so the guard catches only what it was written for.
    constexpr std::size_t maximum_sample_count = 320U * 1280U;
    std::uint64_t sample_width = std::clamp(
        image.width,
        minimum_sample_width,
        maximum_sample_width);
    std::uint64_t sample_height = std::max<std::uint64_t>(
        1U,
        (static_cast<std::uint64_t>(image.height) * sample_width) / image.width);
    const std::uint64_t sample_count = sample_width * sample_height;
    if (sample_count > maximum_sample_count) {
        const double scale = std::sqrt(
            static_cast<double>(maximum_sample_count) / static_cast<double>(sample_count));
        sample_width = std::max<std::uint64_t>(
            1U,
            static_cast<std::uint64_t>(sample_width * scale));
        const double uniform_scale =
            static_cast<double>(sample_width) / static_cast<double>(image.width);
        sample_height = std::max<std::uint64_t>(1U, static_cast<std::uint64_t>(
            static_cast<double>(image.height) * uniform_scale));
    }

    const std::uint32_t bounded_width = static_cast<std::uint32_t>(sample_width);
    const std::uint32_t bounded_height = static_cast<std::uint32_t>(sample_height);

    const std::uint32_t inset_x = std::max(1U, static_cast<std::uint32_t>(bounded_width * 0.06));
    const std::uint32_t inset_y = std::max(1U, static_cast<std::uint32_t>(bounded_height * 0.06));
    if (bounded_width <= inset_x * 2U || bounded_height <= inset_y * 2U) {
        return std::nullopt;
    }

    try {
        std::vector<negaflow::core::Rgba32F> pixels;
        pixels.reserve(static_cast<std::size_t>(bounded_width - (inset_x * 2U)) *
                       (bounded_height - (inset_y * 2U)));
        const negaflow::core::ConstImageView source{
            image.pixels.data(),
            image.pixels.size(),
            image.width,
            image.height,
            image.stride_pixels,
        };
        const DownsampledProxy proxy = downsample_for_statistics(
            source, bounded_width, bounded_height);
        if (proxy.pixels.empty()) {
            return std::nullopt;
        }
        for (std::uint32_t y = inset_y; y < bounded_height - inset_y; ++y) {
            for (std::uint32_t x = inset_x; x < bounded_width - inset_x; ++x) {
                const negaflow::core::Rgba32F pixel =
                    proxy.pixels[(static_cast<std::size_t>(y) * bounded_width) + x];
                if (!std::isfinite(pixel.red) || !std::isfinite(pixel.green) ||
                    !std::isfinite(pixel.blue)) {
                    return std::nullopt;
                }
                pixels.push_back(pixel);
            }
        }
        if (pixels.size() < 64U) {
            return std::nullopt;
        }
        const std::size_t pixel_count = pixels.size();

        const float base_luma = (dmin[0] + dmin[1] + dmin[2]) / 3.0F;
        const float gate = base_luma * 1.12F;
        const float dark_cut = base_luma * 0.15F;
        const float base_ratio = dmin[0] / std::max(dmin[2], 1.0e-4F);
        const std::optional<float> neutral_dark_ratio_cut =
            base_ratio >= 1.5F
            ? std::optional<float>{base_ratio * 0.55F}
            : std::nullopt;
        std::vector<negaflow::core::Rgba32F> film;
        film.reserve(pixels.size());
        for (const negaflow::core::Rgba32F pixel : pixels) {
            const float luma = (pixel.red + pixel.green + pixel.blue) / 3.0F;
            if (luma > gate ||
                (neutral_dark_ratio_cut && luma < dark_cut &&
                 pixel.red / std::max(pixel.blue, 1.0e-4F) < *neutral_dark_ratio_cut)) {
                continue;
            }
            film.push_back(pixel);
        }
        if (film.size() < 64U) {
            film = std::move(pixels);
        }

        std::array<std::vector<float>, 3> channels{};
        for (auto& channel : channels) {
            channel.reserve(film.size());
        }
        for (const negaflow::core::Rgba32F pixel : film) {
            channels[0].push_back(pixel.red);
            channels[1].push_back(pixel.green);
            channels[2].push_back(pixel.blue);
        }
        for (auto& channel : channels) {
            std::sort(channel.begin(), channel.end());
        }

        std::array<float, 3> densest{};
        std::array<float, 3> densest_floor{};
        std::array<float, 3> measured{};
        for (std::size_t channel = 0U; channel < measured.size(); ++channel) {
            densest[channel] = std::max(percentile(channels[channel], 0.002), 1.0e-5F);
            densest_floor[channel] = std::max(
                densest[channel],
                dmin[channel] * std::pow(10.0F, -1.8F));
            measured[channel] =
                std::max(0.4F, std::log10(dmin[channel] / densest_floor[channel]));
        }
        if (debug_enabled()) {
            std::fprintf(
                stderr,
                "[nega-proxy] targetW=%u targetH=%u inset=(%u,%u) pixels=%zu film=%zu "
                "gate=%.6f darkCut=%.6f densest=(%.4f,%.4f,%.4f) "
                "densestFloor=(%.4f,%.4f,%.4f) measuredDmax=(%.4f,%.4f,%.4f)\n",
                bounded_width, bounded_height, inset_x, inset_y, pixel_count, film.size(),
                static_cast<double>(gate), static_cast<double>(dark_cut),
                static_cast<double>(densest[0]), static_cast<double>(densest[1]),
                static_cast<double>(densest[2]), static_cast<double>(densest_floor[0]),
                static_cast<double>(densest_floor[1]), static_cast<double>(densest_floor[2]),
                static_cast<double>(measured[0]), static_cast<double>(measured[1]),
                static_cast<double>(measured[2]));
        }
        const float geometric_mean = std::pow(
            measured[0] * measured[1] * measured[2],
            1.0F / 3.0F);
        const float transition = std::clamp((geometric_mean - 0.42F) / 0.20F, 0.0F, 1.0F);
        const float confidence = transition * transition * (3.0F - (2.0F * transition));
        const float scale = response.normal_range +
            ((geometric_mean - response.normal_range) * confidence);
        std::array<float, 3> result{};
        if (film_type == NegativeFilmType::black_and_white) {
            result = {scale, scale, scale};
        } else {
            for (std::size_t channel = 0U; channel < result.size(); ++channel) {
                result[channel] = scale *
                    (1.0F + ((measured[channel] / geometric_mean) - 1.0F) * confidence);
            }
        }
        // blackInput 은 지표 전용이라 반전 수식에 들어가지 않습니다. 채널이 이미
        // 정렬돼 있어 백분위 한 번이면 되므로 늘 담습니다 - 개발자 디버그 화면이 읽습니다.
        std::array<double, 3> black_input{};
        for (std::size_t channel = 0U; channel < 3U; ++channel) {
            black_input[channel] =
                static_cast<double>(percentile(channels[channel], 0.90)) * 0.97;
        }
        if (out_black_input != nullptr) {
            for (std::size_t channel = 0U; channel < 3U; ++channel) {
                (*out_black_input)[channel] = static_cast<float>(black_input[channel]);
            }
        }
        if (debug_enabled()) {
            double mid_density = 0.0;
            for (std::size_t channel = 0U; channel < 3U; ++channel) {
                mid_density += std::log10(
                    static_cast<double>(dmin[channel]) /
                    std::max(static_cast<double>(percentile(channels[channel], 0.5)), 1.0e-5));
            }
            mid_density = std::max(0.0, mid_density / 3.0);
            std::fprintf(
                stderr,
                "[nega] dmin=(%.4f,%.4f,%.4f) dmaxNorm=(%.4f,%.4f,%.4f) "
                "blackIn=(%.4f,%.4f,%.4f) midD=%.3f\n",
                static_cast<double>(dmin[0]), static_cast<double>(dmin[1]),
                static_cast<double>(dmin[2]), static_cast<double>(result[0]),
                static_cast<double>(result[1]), static_cast<double>(result[2]),
                black_input[0], black_input[1], black_input[2], mid_density);
        }
        return result;
    } catch (const std::bad_alloc&) {
        return std::nullopt;
    }
}

} // namespace

ManualNegativeDevelopResult develop_manual_negative(
    WorkingImage image,
    const ManualNegativeDevelopParameters& parameters) noexcept {
    ManualNegativeDevelopResult result{};
    result.image = std::move(image);

    negaflow::core::PrintResponse response{};
    switch (parameters.film_type) {
        case NegativeFilmType::color:
            response = negaflow::core::color_negative_print_response();
            break;
        case NegativeFilmType::black_and_white:
            response = negaflow::core::black_and_white_negative_print_response();
            break;
        default:
            discard_pixels(result.image);
            return result;
    }

    for (std::size_t channel = 0U; channel < parameters.dmin.size(); ++channel) {
        if (!std::isfinite(parameters.dmin[channel])) {
            discard_pixels(result.image);
            return result;
        }
        result.info.applied_dmin[channel] =
            std::clamp(parameters.dmin[channel], minimum_manual_dmin, maximum_manual_dmin);
        result.info.dmax_normalized[channel] = response.normal_range;
    }
    const auto adaptive = scene_density_range(
        result.image,
        result.info.applied_dmin,
        response,
        parameters.film_type,
        &result.info.black_input);
    if (!parameters.use_preset_response) {
        if (adaptive) {
            result.info.dmax_normalized = *adaptive;
        }
    } else {
        for (const float dmax : parameters.preset_dmax_normalized) {
            if (!std::isfinite(dmax) || dmax <= 0.0F) {
                discard_pixels(result.image);
                return result;
            }
        }
        const float scene_scale = adaptive
            ? std::pow((*adaptive)[0] * (*adaptive)[1] * (*adaptive)[2], 1.0F / 3.0F)
            : response.normal_range;
        if (parameters.film_type == NegativeFilmType::black_and_white) {
            result.info.dmax_normalized = {scene_scale, scene_scale, scene_scale};
        } else {
            const float preset_scale = std::pow(
                parameters.preset_dmax_normalized[0] *
                    parameters.preset_dmax_normalized[1] *
                    parameters.preset_dmax_normalized[2],
                1.0F / 3.0F);
            for (std::size_t channel = 0U; channel < 3U; ++channel) {
                result.info.dmax_normalized[channel] = scene_scale *
                    parameters.preset_dmax_normalized[channel] / preset_scale;
            }
        }
    }

    const negaflow::core::NegativeInversionParameters kernel_parameters{
        result.info.applied_dmin,
        result.info.dmax_normalized,
    };
    const negaflow::core::ConstImageView input{
        result.image.pixels.data(),
        result.image.pixels.size(),
        result.image.width,
        result.image.height,
        result.image.stride_pixels,
    };
    const negaflow::core::ImageView output{
        result.image.pixels.data(),
        result.image.pixels.size(),
        result.image.width,
        result.image.height,
        result.image.stride_pixels,
    };
    // 현상 전체에서 가장 비싼 단계입니다 — 실측으로 프리뷰 856 ms 중 **353 ms(41%)**.
    // 화소마다 채널별 `log10`·`pow`·`exp` 가 돌기 때문입니다.
    //
    // 형태학과 달리 **근사**입니다(곱셈·초월함수). `ApproximateAcceleratorScope`
    // 안에서만 돕니다 — 프리뷰·검출만 그 스코프를 엽니다. 내보내기·골든은 CPU 그대로입니다.
    // 그리고 형태학과 달리 **한 번만** 불리므로 왕복이 1회입니다.
    bool accelerated = false;
    if (approximate_acceleration_allowed()) {
        if (const KernelAccelerator* const table = kernel_accelerator();
            table != nullptr && table->negative_inversion != nullptr) {
            const std::array<float, 4> response_values{
                response.y_ceiling, response.amplitude, response.rate, response.shape};
            accelerated = table->negative_inversion(
                reinterpret_cast<float*>(result.image.pixels.data()),
                result.image.width,
                result.image.height,
                result.image.stride_pixels,
                kernel_parameters.dmin.data(),
                kernel_parameters.dmax_normalized.data(),
                response_values.data());
        }
    }
    result.info.kernel_status = accelerated
        ? negaflow::core::KernelStatus::ok
        : negaflow::core::apply_negative_inversion(
              input,
              output,
              kernel_parameters,
              response);
    if (result.info.kernel_status != negaflow::core::KernelStatus::ok) {
        result.status = ManualNegativeDevelopStatus::kernel_failed;
        discard_pixels(result.image);
        return result;
    }

    if (!parameters.use_preset_response) {
        auto vibrance = apply_muted_scene_vibrance(
            output,
            parameters.film_type == NegativeFilmType::black_and_white);
        result.info.muted_scene_vibrance = vibrance.info;
        if (vibrance.status != negaflow::core::KernelStatus::ok) {
            result.info.kernel_status = vibrance.status;
            result.status = ManualNegativeDevelopStatus::kernel_failed;
            discard_pixels(result.image);
            return result;
        }
    }

    result.status = ManualNegativeDevelopStatus::ok;
    return result;
}

const char* manual_negative_develop_status_name(
    const ManualNegativeDevelopStatus status) noexcept {
    switch (status) {
        case ManualNegativeDevelopStatus::ok:
            return "ok";
        case ManualNegativeDevelopStatus::invalid_parameter:
            return "invalid_parameter";
        case ManualNegativeDevelopStatus::kernel_failed:
            return "kernel_failed";
    }
    return "unknown";
}

const char* negative_film_type_name(const NegativeFilmType film_type) noexcept {
    switch (film_type) {
        case NegativeFilmType::color:
            return "color";
        case NegativeFilmType::black_and_white:
            return "bw";
    }
    return "unknown";
}

} // namespace negaflow::imaging
