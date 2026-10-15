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
    const NegativeFilmType film_type,
    const std::optional<AnalysisRegion>& region,
    std::array<float, 3>* out_black_input = nullptr) noexcept {
    if (!has_compatible_layout(image)) {
        return std::nullopt;
    }
    // 크롭한 사진 영역이 있으면 그 안만 잽니다(홀더·백라이트·이웃 프레임 배제).
    const std::optional<AnalysisPixelRect> rect =
        analysis_measurement_rect(region, image.width, image.height);
    const std::uint32_t measured_width = rect ? rect->width : image.width;
    const std::uint32_t measured_height = rect ? rect->height : image.height;

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
        measured_width,
        minimum_sample_width,
        maximum_sample_width);
    std::uint64_t sample_height = std::max<std::uint64_t>(
        1U,
        (static_cast<std::uint64_t>(measured_height) * sample_width) / measured_width);
    const std::uint64_t sample_count = sample_width * sample_height;
    if (sample_count > maximum_sample_count) {
        const double scale = std::sqrt(
            static_cast<double>(maximum_sample_count) / static_cast<double>(sample_count));
        sample_width = std::max<std::uint64_t>(
            1U,
            static_cast<std::uint64_t>(sample_width * scale));
        const double uniform_scale =
            static_cast<double>(sample_width) / static_cast<double>(measured_width);
        sample_height = std::max<std::uint64_t>(1U, static_cast<std::uint64_t>(
            static_cast<double>(measured_height) * uniform_scale));
    }

    const std::uint32_t bounded_width = static_cast<std::uint32_t>(sample_width);
    const std::uint32_t bounded_height = static_cast<std::uint32_t>(sample_height);

    // 홀더 그림자를 빼려는 6% 인셋입니다. 크롭 영역이면 경계는 이미 잘려 나갔으므로 축소
    // 보간이 크롭 가장자리에서 섞는 두 칸만 버립니다 — 6% 를 그대로 두면 사진 가장자리의
    // 실제 명부가 Dmax 측정에서 빠집니다(macOS `sampleStats` 와 같습니다).
    const std::uint32_t inset_x = rect
        ? 2U : std::max(1U, static_cast<std::uint32_t>(bounded_width * 0.06));
    const std::uint32_t inset_y = rect
        ? 2U : std::max(1U, static_cast<std::uint32_t>(bounded_height * 0.06));
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
        const DownsampledProxy proxy = rect
            ? downsample_region_for_statistics(source, *rect, bounded_width, bounded_height)
            : downsample_for_statistics(source, bounded_width, bounded_height);
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
        const std::uint32_t inner_width = bounded_width - (inset_x * 2U);
        const std::uint32_t inner_height = bounded_height - (inset_y * 2U);
        std::vector<bool> non_film(pixels.size(), false);
        bool any_non_film = false;
        for (std::size_t index = 0U; index < pixels.size(); ++index) {
            const negaflow::core::Rgba32F pixel = pixels[index];
            const float luma = (pixel.red + pixel.green + pixel.blue) / 3.0F;
            non_film[index] = luma > gate ||
                (neutral_dark_ratio_cut && luma < dark_cut &&
                 pixel.red / std::max(pixel.blue, 1.0e-4F) < *neutral_dark_ratio_cut);
            any_non_film = any_non_film || non_film[index];
        }
        // 홀더·백라이트 같은 **두께 있는** 비필름 영역의 가장자리 띠(2 칸)도 버립니다. 축소 보간이
        // 그 가장자리를 필름과 섞은 칸은 게이트를 통과하면서 최농부(p0.2)를 차지합니다 — 2026-10-14
        // 실측: 홀더가 리베이트를 가린 디카 스캔에서 혼합 칸이 Dmax 를 1.8D 바닥으로 채널마다 다르게
        // 잡아 중립 웨지가 R/B 0.72~0.98 로 틀어졌습니다.
        // 먼저 3x3 침식으로 흩어진 점을 지웁니다. 베이스 근처 밝기의 넓은 면에서는 양자화·그레인
        // 수준의 차이로 게이트 판정이 점점이 뒤집히는데, 그 점마다 이웃을 지우면 필름의 91% 가
        // 사라져 남은 칸의 최농부가 입력의 미세한 차이에 크게 흔들렸습니다(macOS 실측: 같은 화상의
        // 원본과 화면용 sRGB 사본에서 Dmax R 0.146 vs 0.238 → 화면·내보내기 불일치). 혼합 띠는
        // 두께 있는 영역 옆에만 생깁니다. macOS `sampleStats` 와 같습니다.
        std::vector<bool> near_non_film = non_film;
        if (any_non_film) {
            std::vector<bool> solid(non_film.size(), false);
            bool any_solid = false;
            for (std::uint32_t y = 0U; y < inner_height; ++y) {
                for (std::uint32_t x = 0U; x < inner_width; ++x) {
                    if (!non_film[static_cast<std::size_t>(y) * inner_width + x]) {
                        continue;
                    }
                    bool all_non_film = true;
                    const std::uint32_t y0 = y > 0U ? y - 1U : 0U;
                    const std::uint32_t y1 = std::min(inner_height - 1U, y + 1U);
                    const std::uint32_t x0 = x > 0U ? x - 1U : 0U;
                    const std::uint32_t x1 = std::min(inner_width - 1U, x + 1U);
                    for (std::uint32_t ny = y0; ny <= y1 && all_non_film; ++ny) {
                        for (std::uint32_t nx = x0; nx <= x1; ++nx) {
                            if (!non_film[static_cast<std::size_t>(ny) * inner_width + nx]) {
                                all_non_film = false;
                                break;
                            }
                        }
                    }
                    solid[static_cast<std::size_t>(y) * inner_width + x] = all_non_film;
                    any_solid = any_solid || all_non_film;
                }
            }
            // 침식된 핵에서 3 칸 = 원래 경계에서 2 칸 띠.
            constexpr std::uint32_t radius = 3U;
            for (std::uint32_t y = 0U; any_solid && y < inner_height; ++y) {
                for (std::uint32_t x = 0U; x < inner_width; ++x) {
                    if (!solid[static_cast<std::size_t>(y) * inner_width + x]) {
                        continue;
                    }
                    const std::uint32_t y0 = y > radius ? y - radius : 0U;
                    const std::uint32_t y1 = std::min(inner_height - 1U, y + radius);
                    const std::uint32_t x0 = x > radius ? x - radius : 0U;
                    const std::uint32_t x1 = std::min(inner_width - 1U, x + radius);
                    for (std::uint32_t ny = y0; ny <= y1; ++ny) {
                        for (std::uint32_t nx = x0; nx <= x1; ++nx) {
                            near_non_film[static_cast<std::size_t>(ny) * inner_width + nx] = true;
                        }
                    }
                }
            }
        }
        const auto keep = [&pixels](const std::vector<bool>& excluded) {
            std::vector<negaflow::core::Rgba32F> kept;
            kept.reserve(pixels.size());
            for (std::size_t index = 0U; index < pixels.size(); ++index) {
                if (!excluded[index]) {
                    kept.push_back(pixels[index]);
                }
            }
            return kept;
        };
        std::vector<negaflow::core::Rgba32F> film = keep(near_non_film);
        if (film.size() < 64U) {
            film = keep(non_film);
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
            // 바닥은 **빈 프레임을 막는 자리**이지 평평한 필름을 부풀리는 자리가 아닙니다.
            // 0.4 는 바랜 필름의 파랑을 그대로 삼켰습니다 - 1980~90 년대 카메라 스캔 다섯 장
            // 중 넷이 파랑에서 정확히 0.40 으로 걸렸고(진짜 값 0.13~0.35), 그만큼 파랑이
            // 과하게 늘어나 사진이 노랗게 나왔습니다. 실제로 관측한 가장 평평한 채널이 0.13
            // 이므로, 그 아래는 필름이 아니라 아무것도 안 찍힌 프레임으로 봅니다.
            measured[channel] =
                std::max(0.10F, std::log10(dmin[channel] / densest_floor[channel]));
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
        // **잰 값을 씁니다.**
        //
        // 앞 판은 잰 범위가 0.42 아래면 그것을 "측정 실패" 로 보고 `normal_range`(≈1.55, 고대비
        // 가정) 로 돌아갔습니다. 그런데 좁은 범위와 실패는 다릅니다 - 오래되어 바랜 필름은
        // 실제로 평평합니다. 측정이 맞는데 틀린 걸로 보고 버리고, 그 고대비 가정이 사진을
        // 검게 눌렀습니다. 1996 년 Kodak Gold 400 카메라 스캔에서 현상 결과가 정상의 13 분의
        // 1 밝기로 나왔고, 그 어두움 때문에 EXPIRED 도 잴 화소가 없어 무력했습니다.
        //
        // 측정이 정말 못 미더운 경우는 값이 작은 것이 아니라 **표본이 없는 것**이고, 그것은
        // 위에서 이미 걸러집니다(프록시 실패, 표본 64 개 미만). 남는 위험은 아무것도 안 찍힌
        // 프레임인데, 그것은 위 채널별 바닥이 묶습니다.
        //
        // 실측: 이 변경으로 값이 달라지는 것은 **잰 범위가 0.42 아래인 파일뿐**입니다. 건강한
        // 스캔은 이미 0.81~0.96 이라 앞 판에서도 confidence 가 1 이었고, 여기서도 비트 단위로
        // 같은 값이 나옵니다.
        const float scale = geometric_mean;
        std::array<float, 3> result{};
        if (film_type == NegativeFilmType::black_and_white) {
            // 흑백은 채널을 갈라 볼 것이 없으므로 세 채널을 같은 값으로 둡니다.
            result = {scale, scale, scale};
        } else {
            // 잰 값을 그대로 씁니다. 앞 판의 `scale * (1 + (measured/gm - 1) * confidence)` 는
            // confidence 가 1 일 때 `measured[channel]` 과 같은 식이었습니다 - 건강한 스캔은
            // 늘 그 자리였으므로 값이 달라지지 않습니다.
            result = measured;
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
    const auto adaptive = parameters.input_gamma_reference_range ? std::nullopt : scene_density_range(
        result.image,
        result.info.applied_dmin,
        parameters.film_type,
        parameters.analysis_region,
        &result.info.black_input);
    if (!parameters.use_preset_response) {
        if (adaptive) {
            result.info.dmax_normalized = *adaptive;
        }
    } else {
        for (const float factor : parameters.preset_range_factor) {
            if (!std::isfinite(factor) || factor <= 0.0F) {
                discard_pixels(result.image);
                return result;
            }
        }
        if (adaptive) {
            result.info.dmax_normalized = *adaptive;
        }
        if (parameters.film_type != NegativeFilmType::black_and_white) {
            for (std::size_t channel = 0U; channel < 3U; ++channel) {
                result.info.dmax_normalized[channel] *= parameters.preset_range_factor[channel];
            }
        }
    }

    if (parameters.input_gamma_reference_range) {
        for (const auto value : *parameters.input_gamma_reference_range) {
            if (!std::isfinite(value) || value <= 0.0F) { discard_pixels(result.image); return result; }
        }
        result.info.dmax_normalized = *parameters.input_gamma_reference_range;
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

    {
        // 필름 모드도 자동 경로와 같은 반전이라 뮤트 장면 생동감을 함께 겁니다(macOS 와 같습니다).
        auto vibrance = apply_muted_scene_vibrance(
            output,
            parameters.film_type == NegativeFilmType::black_and_white,
            parameters.analysis_region);
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
