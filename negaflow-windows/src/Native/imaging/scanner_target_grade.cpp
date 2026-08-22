#include "negaflow/imaging/scanner_target_grade.h"

#include "negaflow/core/parallel_rows.h"
#include "negaflow/imaging/kernel_accelerator.h"

#include "scanner_target_color.h"
#include "scanner_target_measure.h"
#include "scanner_target_profile.h"
#include "scanner_target_response.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <new>
#include <string_view>
#include <vector>

namespace negaflow::imaging {
namespace {

using namespace negaflow::imaging::scanner_target_detail;

void apply_profile_grade(
    const negaflow::core::ImageView image,
    const TargetProfile& profile,
    const double strength,
    const double anchor_weight,
    const double scene_median,
    const bool monochrome) noexcept {
    const double chroma_keep = 1.0 - std::min(anchor_weight, 0.65);
    std::array<double, 9U> tone{};
    for (std::size_t i = 0U; i < tone.size(); ++i) {
        tone[i] = clamp(
            profile.tone_xs[i] + (profile.tone_delta[i] * strength),
            0.002,
            0.998);
    }
    const double clamped_median = clamp(
        scene_median, profile.tone_xs.front(), profile.tone_xs.back());
    const double mapped_median = relative_tone(
        clamped_median, profile.tone_xs, tone);
    const double offset = std::round(
        ((mapped_median - clamped_median) * anchor_weight) / 0.004) * 0.004;
    if (std::abs(offset) > 1.0e-9) {
        for (std::size_t i = 0U; i < tone.size(); ++i) {
            tone[i] = clamp(
                tone[i] - (offset * smoothstep(0.05, 0.25, profile.tone_xs[i])),
                0.002,
                0.998);
        }
    }

    // GPU 판이 받을 값입니다. 표를 두 곳에서 만들면 그 순간 두 벌이 되므로 여기서
    // 한 번 만들고, CPU 루프와 GPU 둘 다 **같은 것**을 씁니다.
    ScannerTargetGradeSetup setup{};
    for (std::size_t i = 0U; i < ScannerTargetGradeSetup::tone_knots; ++i) {
        setup.tone_xs[i] = static_cast<float>(profile.tone_xs[i]);
        setup.tone_ys[i] = static_cast<float>(tone[i]);
    }
    setup.neutral_count = static_cast<std::uint32_t>(std::min(
        profile.neutral_count, ScannerTargetGradeSetup::neutral_capacity));
    for (std::size_t i = 0U; i < setup.neutral_count; ++i) {
        setup.neutral_bins[i][0] = static_cast<float>(profile.neutral_bins[i].luma);
        setup.neutral_bins[i][1] = static_cast<float>(profile.neutral_bins[i].a);
        setup.neutral_bins[i][2] = static_cast<float>(profile.neutral_bins[i].b);
    }
    setup.hue_count = static_cast<std::uint32_t>(
        std::min(profile.hue_count, ScannerTargetGradeSetup::hue_capacity));
    for (std::size_t i = 0U; i < setup.hue_count; ++i) {
        setup.hue_anchors[i][0] = static_cast<float>(profile.hue_anchors[i].hue);
        setup.hue_anchors[i][1] = static_cast<float>(profile.hue_anchors[i].gain);
        setup.hue_anchors[i][2] = static_cast<float>(profile.hue_anchors[i].rotation);
    }
    for (std::size_t i = 0U; i < ScannerTargetGradeSetup::chroma_capacity; ++i) {
        setup.chroma_bands[i][0] = static_cast<float>(profile.chroma_bands[i].luma);
        setup.chroma_bands[i][1] = static_cast<float>(profile.chroma_bands[i].gain);
    }
    setup.strength = static_cast<float>(strength);
    setup.chroma_keep = static_cast<float>(chroma_keep);
    setup.monochrome = monochrome;

    // **엔진에서 가장 비싼 화소별 커널입니다** — 노리츠 프리뷰 실측 58,995 ms
    // (병렬화 뒤 16,201 ms)로 전체의 90% 를 넘었습니다. 화소마다 `transformed_srgb`
    // 를 두 번 돌리고 그 안에 Lab 왕복·`atan2`·`log`·`exp`·`pow` 가 줄줄이 있습니다.
    //
    // **근사입니다**(CPU 는 Lab 왕복이 `double`). `ApproximateAcceleratorScope`
    // 안에서만 돕니다 — 내보내기·골든은 CPU 그대로입니다.
    if (approximate_acceleration_allowed() && image.stride_pixels <= 0xFFFFFFFFULL) {
        if (const KernelAccelerator* const table = kernel_accelerator();
            table != nullptr && table->scanner_target_grade != nullptr) {
            if (table->scanner_target_grade(
                    reinterpret_cast<float*>(image.pixels),
                    image.width,
                    image.height,
                    static_cast<std::uint32_t>(image.stride_pixels),
                    &setup)) {
                return;
            }
        }
    }

    // **행마다 독립입니다.** 화소는 자기 값만 읽고 자기 자리에만 씁니다 —
    // 쪼개도 값이 비트 단위로 같습니다. 앞 판은 직렬이었고, 실측으로 이 단계가
    // 엔진에서 가장 비쌌습니다(노리츠 프리뷰 58,995 ms, 전체의 97.5%).
    //
    // `work_units` 에 **행 수가 아니라 화소 수 × 화소당 무게**를 넘깁니다.
    // 행 수(3,401)만 넘기면 문턱(1M)을 못 넘어 병렬화가 **조용히 꺼집니다** —
    // 플레이북 21절이 적은 함정입니다. 화소마다 `transformed_srgb` 를 두 번
    // 돌리므로 무게를 2 로 둡니다.
    const std::uint64_t work_units =
        static_cast<std::uint64_t>(image.width) * image.height * 2ULL;
    negaflow::core::for_each_row_block(
        image.height,
        work_units,
        [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
            for (std::uint32_t y = first_row; y < first_row + row_count; ++y) {
                for (std::uint32_t x = 0U; x < image.width; ++x) {
                    auto& pixel = image.pixels[
                        static_cast<std::size_t>(y) * image.stride_pixels + x];
                    const Rgb encoded{
                        srgb_encode(pixel.red),
                        srgb_encode(pixel.green),
                        srgb_encode(pixel.blue),
                    };
                    const double low = std::min({encoded.red, encoded.green, encoded.blue});
                    const double high = std::max({encoded.red, encoded.green, encoded.blue});
                    const double domain_weight = smoothstep(0.0, 0.02, low) *
                        (1.0 - smoothstep(0.98, 1.0, high));
                    if (domain_weight <= 0.0) continue;
                    const Rgb candidate = transformed_srgb(
                        encoded, profile, tone, strength, chroma_keep, monochrome, false);
                    const Rgb reciprocal = transformed_srgb(
                        encoded, profile, tone, strength, chroma_keep, monochrome, true);
                    const double scale = gamut_scale(encoded, candidate, reciprocal);
                    const Rgb graded{
                        srgb_decode(encoded.red + ((candidate.red - encoded.red) * scale)),
                        srgb_decode(encoded.green + ((candidate.green - encoded.green) * scale)),
                        srgb_decode(encoded.blue + ((candidate.blue - encoded.blue) * scale)),
                    };
                    pixel.red = static_cast<float>(
                        pixel.red + ((graded.red - pixel.red) * domain_weight));
                    pixel.green = static_cast<float>(
                        pixel.green + ((graded.green - pixel.green) * domain_weight));
                    pixel.blue = static_cast<float>(
                        pixel.blue + ((graded.blue - pixel.blue) * domain_weight));
                }
            }
        });
}

void apply_noritsu_texture_cpu(
    const negaflow::core::ImageView image,
    std::vector<Rgb>& scratch,
    const ScannerTargetTextureSetup& texture) {
    std::array<double, 5U> weights{};
    for (std::size_t i = 0U; i < ScannerTargetTextureSetup::taps; ++i) {
        weights[i] = texture.weights[i];
    }

    // 하드 게이트: `low < 0 || high > 1` 이면 화소를 통째로 통과시킵니다.
    // 그 경계 근처에서 CPU(`double`)와 GPU(float)의 1ulp 차이가
    // "질감을 얹는다/안 얹는다" 를 뒤집습니다. 시험은 최대 오차와 이탈 화소
    // 비율을 같이 겁니다.

    const auto coordinate = [](const std::int64_t value, const std::uint32_t limit) {
        return static_cast<std::uint32_t>(std::clamp<std::int64_t>(value, 0, limit - 1U));
    };
    // 수평 저역. 행마다 독립입니다 — 자기 행만 읽고 자기 행만 씁니다.
    const std::uint64_t work_units =
        static_cast<std::uint64_t>(image.width) * image.height * 5ULL;
    negaflow::core::for_each_row_block(
        image.height,
        work_units,
        [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
            for (std::uint32_t y = first_row; y < first_row + row_count; ++y) {
                for (std::uint32_t x = 0U; x < image.width; ++x) {
                    Rgb sum{};
                    for (std::int64_t k = -2; k <= 2; ++k) {
                        const auto sample = image.pixels[
                            static_cast<std::size_t>(y) * image.stride_pixels +
                            coordinate(static_cast<std::int64_t>(x) + k, image.width)];
                        const double w = weights[static_cast<std::size_t>(k + 2)];
                        sum.red += sample.red * w;
                        sum.green += sample.green * w;
                        sum.blue += sample.blue * w;
                    }
                    scratch[static_cast<std::size_t>(y) * image.width + x] = sum;
                }
            }
        });
    // 수직 저역 + 언샤프. `scratch` 는 여기서 **읽기 전용**이고 화소는 자기 자리에만
    // 쓰므로 행 블록이 값을 바꾸지 않습니다.
    negaflow::core::for_each_row_block(
        image.height,
        work_units,
        [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
    for (std::uint32_t y = first_row; y < first_row + row_count; ++y) {
        for (std::uint32_t x = 0U; x < image.width; ++x) {
            Rgb blur{};
            for (std::int64_t k = -2; k <= 2; ++k) {
                const Rgb sample = scratch[static_cast<std::size_t>(coordinate(
                    static_cast<std::int64_t>(y) + k, image.height)) * image.width + x];
                const double w = weights[static_cast<std::size_t>(k + 2)];
                blur.red += sample.red * w; blur.green += sample.green * w; blur.blue += sample.blue * w;
            }
            auto& pixel = image.pixels[static_cast<std::size_t>(y) * image.stride_pixels + x];
            const double low = std::min({pixel.red, pixel.green, pixel.blue});
            const double high = std::max({pixel.red, pixel.green, pixel.blue});
            const double original_luma = (0.2126 * pixel.red) + (0.7152 * pixel.green) + (0.0722 * pixel.blue);
            if (low < 0.0 || high > 1.0 ||
                original_luma <= static_cast<double>(texture.luma_gate)) {
                continue;
            }
            const double blur_luma = clamp((0.2126 * blur.red) + (0.7152 * blur.green) +
                (0.0722 * blur.blue), 0.0, 1.0);
            const double y_original = srgb_encode(original_luma);
            const double y_blur = srgb_encode(blur_luma);
            const double floor_y = std::max(
                y_original * static_cast<double>(texture.floor_ratio),
                std::min(y_original, static_cast<double>(texture.floor_absolute)));
            const double y_new = clamp(
                y_original + (texture.amount * (y_original - y_blur)), floor_y, 1.0);
            double gain = srgb_decode(y_new) / original_luma;
            const double maximum = high * gain;
            if (maximum > 1.0) gain /= maximum;
            pixel.red = static_cast<float>(pixel.red * gain);
            pixel.green = static_cast<float>(pixel.green * gain);
            pixel.blue = static_cast<float>(pixel.blue * gain);
        }
    }
        });
}

} // namespace

ScannerTargetTextureSetup scanner_target_texture_setup() noexcept {
    // σ ≈ 0.9 의 이산 가우시안 5탭과 감마 도메인 USM 게인입니다
    // (macOS `noritsuSharpenRadius = 0.9`, `noritsuSharpenAmount = 0.6`).
    // 플로어·루마 게이트는 macOS `noritsuTexture` 본문 그대로입니다.
    ScannerTargetTextureSetup setup{};
    setup.weights[0] = 0.037657F;
    setup.weights[1] = 0.239936F;
    setup.weights[2] = 0.444814F;
    setup.weights[3] = 0.239936F;
    setup.weights[4] = 0.037657F;
    setup.amount = 0.6F;
    setup.floor_ratio = 0.45F;
    setup.floor_absolute = 0.008F;
    setup.luma_gate = 1.0e-5F;
    return setup;
}

negaflow::core::KernelStatus apply_noritsu_texture(
    const negaflow::core::ImageView image) noexcept {
    const auto view_status = negaflow::core::validate_image_view(image);
    if (view_status != negaflow::core::KernelStatus::ok) {
        return view_status;
    }
    const ScannerTargetTextureSetup setup = scanner_target_texture_setup();
    if (approximate_acceleration_allowed() && image.stride_pixels <= 0xFFFFFFFFULL) {
        if (const KernelAccelerator* const table = kernel_accelerator();
            table != nullptr && table->noritsu_texture != nullptr) {
            if (table->noritsu_texture(
                    reinterpret_cast<float*>(image.pixels),
                    image.width,
                    image.height,
                    static_cast<std::uint32_t>(image.stride_pixels),
                    &setup)) {
                return negaflow::core::KernelStatus::ok;
            }
        }
    }
    try {
        std::vector<Rgb> scratch(
            static_cast<std::size_t>(image.width) * image.height);
        apply_noritsu_texture_cpu(image, scratch, setup);
    } catch (const std::bad_alloc&) {
        return negaflow::core::KernelStatus::buffer_too_small;
    }
    return negaflow::core::KernelStatus::ok;
}

negaflow::core::KernelStatus apply_scanner_target_grade(
    const negaflow::core::ImageView image,
    const ScannerTargetStyle target,
    const bool monochrome,
    const bool positive,
    const std::wstring_view scanner_profile_id,
    ScannerTargetGradeInfo& info) noexcept {
    info = {};
    const auto input = negaflow::core::ConstImageView{
        image.pixels, image.pixel_capacity, image.width, image.height, image.stride_pixels};
    const auto view_status = negaflow::core::validate_image_view(image);
    if (view_status != negaflow::core::KernelStatus::ok) return view_status;
    const auto finite_status = negaflow::core::validate_finite_pixels(input);
    if (finite_status != negaflow::core::KernelStatus::ok) return finite_status;

    try {
        const TargetProfile& profile = profile_for(target);
        const double strength = positive ? 0.5 : 1.0;
        double scene_median = 0.5;
        const double anchor_weight = scene_anchor_weight(image, scene_median);
        info.scene_anchor_weight = static_cast<float>(anchor_weight);

        if (monochrome) {
            for (std::uint32_t y = 0U; y < image.height; ++y) {
                for (std::uint32_t x = 0U; x < image.width; ++x) {
                    auto& pixel = image.pixels[static_cast<std::size_t>(y) * image.stride_pixels + x];
                    const float gray = (0.2126F * pixel.red) + (0.7152F * pixel.green) +
                        (0.0722F * pixel.blue);
                    pixel.red = gray; pixel.green = gray; pixel.blue = gray;
                }
            }
        }

        apply_profile_grade(
            image, profile, strength, anchor_weight, scene_median, monochrome);
        if (!positive) {
            if (const TargetProfile* const relative =
                    relative_profile_for(target, scanner_profile_id)) {
                apply_profile_grade(
                    image, *relative, 1.0, anchor_weight, scene_median, monochrome);
                info.relative_signature_applied = true;
            }
        }

        if (target == ScannerTargetStyle::noritsu) {
            const auto texture_status = apply_noritsu_texture(image);
            if (texture_status != negaflow::core::KernelStatus::ok) {
                return texture_status;
            }
            info.texture_applied = true;
        }
    } catch (const std::bad_alloc&) {
        return negaflow::core::KernelStatus::buffer_too_small;
    }

    const auto output_status = negaflow::core::validate_finite_pixels(input);
    if (output_status != negaflow::core::KernelStatus::ok) {
        return negaflow::core::KernelStatus::non_finite_output;
    }
    info.applied = true;
    return negaflow::core::KernelStatus::ok;
}

} // namespace negaflow::imaging
