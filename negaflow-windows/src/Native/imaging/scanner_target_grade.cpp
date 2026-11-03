#include "negaflow/imaging/scanner_target_grade.h"

#include "negaflow/core/parallel_rows.h"
#include "negaflow/imaging/kernel_accelerator.h"

#include "scanner_target_color.h"
#include "scanner_target_profile.h"
#include "scanner_target_rendering.h"
#include "scanner_target_response.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <new>
#include <string_view>
#include <vector>

namespace negaflow::imaging {

namespace {
std::atomic<std::uint64_t> target_grade_gpu_runs{0U};
std::atomic<std::uint64_t> target_grade_cpu_runs{0U};
} // namespace

void note_target_grade_route(const bool used_gpu) noexcept {
    if (used_gpu) {
        target_grade_gpu_runs.fetch_add(1U, std::memory_order_relaxed);
    } else {
        target_grade_cpu_runs.fetch_add(1U, std::memory_order_relaxed);
    }
}

TargetGradeRouteCounts target_grade_route_counts() noexcept {
    return {
        target_grade_gpu_runs.load(std::memory_order_relaxed),
        target_grade_cpu_runs.load(std::memory_order_relaxed),
    };
}
namespace {

using namespace negaflow::imaging::scanner_target_detail;

// 사용자가 고른 필름 프로파일의 실측 상대 차분(감마 도메인 톤 + Lab 색)입니다. 장면을 읽지
// 않습니다 — 예전의 평탄 장면 노출 앵커·채도 수축은 타깃이 고정 변환이 되면서 걷어냈습니다.
void apply_profile_grade(
    const negaflow::core::ImageView image,
    const TargetProfile& profile,
    const bool monochrome) noexcept {
    const double strength = 1.0;
    const double chroma_keep = 1.0;
    std::array<double, 9U> tone{};
    for (std::size_t i = 0U; i < tone.size(); ++i) {
        tone[i] = clamp(
            profile.tone_xs[i] + (profile.tone_delta[i] * strength),
            0.002,
            0.998);
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
    setup.color_density = static_cast<float>(profile.color_density);

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
                note_target_grade_route(true);
                return;
            }
            note_target_grade_route(false);
        } else {
            note_target_grade_route(false);
        }
    } else {
        note_target_grade_route(false);
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
                    // 정방향과 역방향은 입력이 같습니다 — 공통 계산을 한 번만 합니다.
                    // 값은 예전과 비트 단위로 같습니다(`transformed_srgb_pair` 주석 참고).
                    const auto pair = transformed_srgb_pair(
                        encoded, profile, tone, strength, chroma_keep, monochrome);
                    const Rgb candidate = pair.candidate;
                    const Rgb reciprocal = pair.reciprocal;
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
    std::array<double, ScannerTargetTextureSetup::max_taps> weights{};
    for (std::size_t i = 0U; i < texture.tap_count; ++i) {
        weights[i] = texture.weights[i];
    }
    const auto support = static_cast<std::int64_t>(texture.tap_count / 2U);

    // 하드 게이트: `low < 0 || high > 1` 이면 화소를 통째로 통과시킵니다.
    // 그 경계 근처에서 CPU(`double`)와 GPU(float)의 1ulp 차이가
    // "질감을 얹는다/안 얹는다" 를 뒤집습니다. 시험은 최대 오차와 이탈 화소
    // 비율을 같이 겁니다.

    const auto coordinate = [](const std::int64_t value, const std::uint32_t limit) {
        return static_cast<std::uint32_t>(std::clamp<std::int64_t>(value, 0, limit - 1U));
    };
    // 수평 저역. 행마다 독립입니다 — 자기 행만 읽고 자기 행만 씁니다.
    const std::uint64_t work_units =
        static_cast<std::uint64_t>(image.width) * image.height * texture.tap_count;
    negaflow::core::for_each_row_block(
        image.height,
        work_units,
        [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
            for (std::uint32_t y = first_row; y < first_row + row_count; ++y) {
                for (std::uint32_t x = 0U; x < image.width; ++x) {
                    Rgb sum{};
                    for (std::int64_t k = -support; k <= support; ++k) {
                        const auto sample = image.pixels[
                            static_cast<std::size_t>(y) * image.stride_pixels +
                            coordinate(static_cast<std::int64_t>(x) + k, image.width)];
                        const double w = weights[static_cast<std::size_t>(k + support)];
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
            for (std::int64_t k = -support; k <= support; ++k) {
                const Rgb sample = scratch[static_cast<std::size_t>(coordinate(
                    static_cast<std::int64_t>(y) + k, image.height)) * image.width + x];
                const double w = weights[static_cast<std::size_t>(k + support)];
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

// 스캐너 렌더링을 화소마다 계산합니다. 근사 범위(프리뷰)에서는 GPU 가 같은 식을 float 로
// 돌고, 화상이 GPU 에 머물러 있으면 내려받지 않습니다. CPU 판은 행 블록 병렬입니다 — 화소는
// 자기 값만 읽고 자기 자리에만 쓰므로 쪼개도 결과가 비트 단위로 같습니다.
void apply_rendering(
    const negaflow::core::ImageView image,
    const RenderingCurves& curves,
    const bool monochrome,
    const double strength) noexcept {
    const ScannerRenderingSetup setup = rendering_setup(curves, monochrome, strength);
    if (approximate_acceleration_allowed() && image.stride_pixels <= 0xFFFFFFFFULL) {
        if (const KernelAccelerator* const table = kernel_accelerator();
            table != nullptr && table->scanner_rendering != nullptr &&
            table->scanner_rendering(
                reinterpret_cast<float*>(image.pixels),
                image.width,
                image.height,
                static_cast<std::uint32_t>(image.stride_pixels),
                &setup)) {
            note_target_grade_route(true);
            return;
        }
    }
    note_target_grade_route(false);
    const std::uint64_t work_units = static_cast<std::uint64_t>(image.width) * image.height;
    negaflow::core::for_each_row_block(
        image.height,
        work_units,
        [&](const std::uint32_t first_row, const std::uint32_t row_count) noexcept {
            for (std::uint32_t y = first_row; y < first_row + row_count; ++y) {
                for (std::uint32_t x = 0U; x < image.width; ++x) {
                    auto& pixel = image.pixels[
                        static_cast<std::size_t>(y) * image.stride_pixels + x];
                    Rgb input{pixel.red, pixel.green, pixel.blue};
                    if (monochrome) {
                        const double gray = luma(input);
                        input = {gray, gray, gray};
                    }
                    const Rgb out = render_linear(input, curves, monochrome);
                    pixel.red = static_cast<float>(input.red + ((out.red - input.red) * strength));
                    pixel.green = static_cast<float>(
                        input.green + ((out.green - input.green) * strength));
                    pixel.blue = static_cast<float>(
                        input.blue + ((out.blue - input.blue) * strength));
                }
            }
        });
}

} // namespace

ScannerTargetTextureSetup scanner_target_texture_setup(const std::uint32_t long_edge) noexcept {
    // macOS `noritsuSharpenSigma`: 실기 35mm 출력 긴 변 3089px 에서 σ 0.9px, 긴 변에 비례.
    // 가중치는 그 σ 의 표본 가우시안이고(σ 0.9 이면 예전 5탭 값과 같습니다), 지지는 ±3σ 입니다.
    // 플로어·루마 게이트는 macOS `noritsuTexture` 본문 그대로입니다.
    ScannerTargetTextureSetup setup{};
    setup.amount = 0.6F;
    setup.floor_ratio = 0.45F;
    setup.floor_absolute = 0.008F;
    setup.luma_gate = 1.0e-5F;
    const double sigma = 0.9 * static_cast<double>(long_edge) / 3089.0;
    if (!(sigma >= 0.05)) {
        return setup;
    }
    const auto support = static_cast<std::uint32_t>(std::min<double>(
        std::ceil(3.0 * sigma), static_cast<double>((ScannerTargetTextureSetup::max_taps - 1U) / 2U)));
    setup.tap_count = (2U * support) + 1U;
    double sum = 0.0;
    std::array<double, ScannerTargetTextureSetup::max_taps> raw{};
    for (std::uint32_t i = 0U; i < setup.tap_count; ++i) {
        const double k = static_cast<double>(i) - static_cast<double>(support);
        raw[i] = std::exp(-(k * k) / (2.0 * sigma * sigma));
        sum += raw[i];
    }
    for (std::uint32_t i = 0U; i < setup.tap_count; ++i) {
        setup.weights[i] = static_cast<float>(raw[i] / sum);
    }
    return setup;
}

negaflow::core::KernelStatus apply_noritsu_texture(
    const negaflow::core::ImageView image) noexcept {
    const auto view_status = negaflow::core::validate_image_view(image);
    if (view_status != negaflow::core::KernelStatus::ok) {
        return view_status;
    }
    const ScannerTargetTextureSetup setup =
        scanner_target_texture_setup(std::max(image.width, image.height));
    if (setup.tap_count == 0U) {
        return negaflow::core::KernelStatus::ok;
    }
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

namespace {

// 화상이 GPU 에 머물러 있으면 유한성도 거기서 봅니다. 호스트 화소는 낡았을 수 있고, 전체를
// 내려 CPU 로 훑으면 사슬이 GPU 에서 끊깁니다(`muted_scene_vibrance.cpp` 와 같은 규칙).
[[nodiscard]] negaflow::core::KernelStatus validate_finite(
    const negaflow::core::ImageView image) noexcept {
    if (const KernelAccelerator* const table = kernel_accelerator();
        table != nullptr && table->resident_finite_check != nullptr &&
        image.stride_pixels <= 0xFFFFFFFFULL) {
        bool all_finite = false;
        if (table->resident_finite_check(
                reinterpret_cast<const float*>(image.pixels),
                image.width,
                image.height,
                static_cast<std::uint32_t>(image.stride_pixels),
                &all_finite)) {
            return all_finite ? negaflow::core::KernelStatus::ok
                              : negaflow::core::KernelStatus::non_finite_input;
        }
    }
    return negaflow::core::validate_finite_pixels(negaflow::core::ConstImageView{
        image.pixels, image.pixel_capacity, image.width, image.height, image.stride_pixels});
}

}  // namespace

negaflow::core::KernelStatus apply_scanner_target_grade(
    const negaflow::core::ImageView image,
    const ScannerTargetStyle target,
    const bool monochrome,
    const bool positive,
    const std::wstring_view scanner_profile_id,
    ScannerTargetGradeInfo& info) noexcept {
    info = {};
    const auto view_status = negaflow::core::validate_image_view(image);
    if (view_status != negaflow::core::KernelStatus::ok) return view_status;
    const auto finite_status = validate_finite(image);
    if (finite_status != negaflow::core::KernelStatus::ok) return finite_status;

    try {
        // 1. 고정 렌더링(흑백은 커널 안에서 luma 로 붕괴합니다).
        apply_rendering(
            image,
            rendering_curves(rendering_for(target)),
            monochrome,
            positive ? rendering_positive_strength : 1.0);
        // 2. 사용자가 고른 필름 프로파일의 실측 상대 차분(네거티브만).
        if (!positive) {
            if (const TargetProfile* const relative =
                    relative_profile_for(target, scanner_profile_id)) {
                apply_profile_grade(image, *relative, monochrome);
                info.relative_signature_applied = true;
            }
        }
        // 3. NORITSU 장치 질감.
        if (target == ScannerTargetStyle::noritsu) {
            const auto texture_status = apply_noritsu_texture(image);
            if (texture_status != negaflow::core::KernelStatus::ok) {
                return texture_status;
            }
            info.texture_applied =
                scanner_target_texture_setup(std::max(image.width, image.height)).tap_count > 0U;
        }
    } catch (const std::bad_alloc&) {
        return negaflow::core::KernelStatus::buffer_too_small;
    }

    const auto output_status = validate_finite(image);
    if (output_status != negaflow::core::KernelStatus::ok) {
        return negaflow::core::KernelStatus::non_finite_output;
    }
    info.applied = true;
    return negaflow::core::KernelStatus::ok;
}

} // namespace negaflow::imaging
