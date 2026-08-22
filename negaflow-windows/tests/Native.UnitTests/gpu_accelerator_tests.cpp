// 파이프라인 GPU 가속 진입점 시험.
//
// 커널 동치 시험은 커널이 맞는지를 봅니다. **이 시험은 그 커널이 실제로 파이프라인에서
// 도는지**를 봅니다 — 앞 판의 가장 큰 구멍이 "커널은 정확한데 아무도 안 부른다" 였습니다.
//
// 보는 것 셋:
// ① 정책이 `cpu_only` 면 GPU 가 **손대지 않습니다.** 내보내기·골든이 여기 걸려 있습니다.
// ② 정책이 `allowed` 면 **실제로 처리합니다**(`handled == true`). 안 돌면 이 시험이 실패합니다.
// ③ 처리한 결과가 CPU 판과 허용 오차 안입니다. 적용 플래그도 CPU 와 같아야 합니다 —
// 게이트를 하나라도 빠뜨리면 여기서 걸립니다.

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <utility>
#include <vector>

#include "export/support/preview.h"

#include "negaflow/core/negative_inversion.h"
#include "negaflow/imaging/film_scan_denoise.h"
#include "negaflow/imaging/image_transform.h"
#include "negaflow/imaging/kernel_accelerator.h"
#include "negaflow/imaging/scene_correction.h"
#include "negaflow/imaging/working_tone_adjuster.h"
#include "negaflow/pipeline/gpu_accelerator.h"

namespace {

using negaflow::core::Rgba32F;
using negaflow::imaging::FilmScanDenoiseParameters;
using negaflow::imaging::WorkingImage;
using negaflow::imaging::WorkingToneAdjustParameters;
using negaflow::pipeline::GpuAccelerator;
using negaflow::pipeline::GpuUsePolicy;

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

// 톤 커널은 1e-5, 디노이즈 사슬은 감마 리프트의 `pow` 때문에 그보다 큽니다
// (`gpu_film_scan_stage.h` 의 설명). 두 상한을 따로 둡니다.
constexpr float tone_tolerance = 1.0e-5F;
constexpr float denoise_tolerance = 1.0e-4F;
// 장면 보정은 표본 누적이 CPU double / GPU float 이라 계수가 마지막 자리에서 갈립니다.
// 8비트 출력 한 칸이 1/255 = 3.9e-3 이므로 그보다 훨씬 아래여야 "눈에 안 보인다" 입니다.
constexpr float scene_tolerance = 5.0e-4F;

// 타일 한 변(512)을 지나가게 잡습니다 — 디노이즈가 타일 경계를 실제로 지나야 의미가 있습니다.
constexpr std::uint32_t width = 600U;
constexpr std::uint32_t height = 96U;

[[nodiscard]] WorkingImage make_image() {
    WorkingImage image{};
    image.width = width;
    image.height = height;
    image.stride_pixels = width;
    image.pixels.resize(static_cast<std::size_t>(width) * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const std::uint32_t seed = (x * 73856093U) ^ (y * 19349663U);
            const std::uint32_t mixed = (seed ^ (seed >> 13U)) * 1274126177U;
            const float noise = static_cast<float>(mixed >> 8U) / 16777216.0F;
            const float ramp = static_cast<float>(x) / static_cast<float>(width - 1U);
            const float base = std::clamp(ramp * 0.9F + (noise - 0.5F) * 0.08F, 0.0F, 1.0F);
            image.pixels[(static_cast<std::size_t>(y) * width) + x] = Rgba32F{
                base,
                std::clamp(base * 0.85F, 0.0F, 1.0F),
                std::clamp(0.9F - base, 0.0F, 1.0F),
                1.0F};
        }
    }
    return image;
}

// 색이 치우친 화상입니다. 채널 중앙값이 서로 달라야 중성 균형 게이트를 지납니다.
[[nodiscard]] WorkingImage make_cast_image() {
    WorkingImage image = make_image();
    for (Rgba32F& pixel : image.pixels) {
        pixel.red = std::clamp((pixel.red * 0.55F) + 0.30F, 0.0F, 1.0F);
        pixel.green = std::clamp((pixel.green * 0.55F) + 0.42F, 0.0F, 1.0F);
        pixel.blue = std::clamp((pixel.blue * 0.55F) + 0.18F, 0.0F, 1.0F);
    }
    return image;
}

[[nodiscard]] float worst_delta(
    const std::vector<Rgba32F>& reference,
    const std::vector<Rgba32F>& measured) noexcept {
    float worst = 0.0F;
    if (reference.size() != measured.size()) {
        return 1.0F;
    }
    for (std::size_t index = 0U; index < reference.size(); ++index) {
        worst = std::max(worst, std::abs(reference[index].red - measured[index].red));
        worst = std::max(worst, std::abs(reference[index].green - measured[index].green));
        worst = std::max(worst, std::abs(reference[index].blue - measured[index].blue));
        worst = std::max(worst, std::abs(reference[index].alpha - measured[index].alpha));
    }
    return worst;
}

void tone_path_runs_on_gpu() {
    WorkingToneAdjustParameters parameters{};
    parameters.exposure_stops = 0.6F;
    parameters.basic.contrast = 0.35F;
    parameters.basic.shadows = -0.20F;
    parameters.basic.whites = 1.4F; // ±1 을 넘는 값 — 엔진이 받아야 합니다.
    parameters.curve.lights = 0.30F;
    parameters.curve.darks = -0.25F;
    parameters.color_mixer.saturation[2] = 0.4F;
    parameters.color_grading.shadows = {35.0F, 0.5F, 0.15F};
    parameters.color_grading.blending = 0.5F;
    parameters.primary_calibration.red_hue = 0.2F;

    // ① `cpu_only` 는 손대지 않습니다.
    {
        WorkingImage image = make_image();
        const std::vector<Rgba32F> before = image.pixels;
        const auto outcome = GpuAccelerator::shared().apply_working_tone_adjustments(
            GpuUsePolicy::cpu_only, image, parameters, {});
        expect(!outcome.handled, "cpu_only must not use the GPU");
        expect(worst_delta(before, image.pixels) == 0.0F, "cpu_only must leave pixels alone");
    }

    // CPU 기준값.
    const auto cpu = negaflow::imaging::apply_working_tone_adjustments(make_image(), parameters);
    if (cpu.status != negaflow::imaging::WorkingToneAdjustStatus::ok) {
        expect(false, "the CPU tone path must succeed");
        return;
    }

    // ② `allowed` 는 실제로 처리해야 합니다.
    WorkingImage image = make_image();
    const auto outcome = GpuAccelerator::shared().apply_working_tone_adjustments(
        GpuUsePolicy::allowed, image, parameters, {});
    if (!GpuAccelerator::shared().available()) {
        std::cout << "[gpu] accelerator unavailable — the CPU path is the only one here\n";
        expect(!outcome.handled, "an unavailable accelerator must not claim the work");
        return;
    }
    expect(outcome.handled, "the tone path must actually run on the GPU");
    if (!outcome.handled) {
        return;
    }

    // ③ 값과 적용 플래그가 CPU 와 같아야 합니다.
    const float worst = worst_delta(cpu.image.pixels, image.pixels);
    if (worst > tone_tolerance) {
        std::cerr << "FAIL: tone gpu/cpu max delta " << worst << '\n';
        ++failures;
    } else {
        std::cout << "[gpu] pipeline tone max delta " << worst << '\n';
    }
    expect(outcome.info.exposure_applied == cpu.info.exposure_applied, "exposure gate agrees");
    expect(outcome.info.basic_tone_applied == cpu.info.basic_tone_applied, "basic gate agrees");
    expect(
        outcome.info.parametric_curve_applied == cpu.info.parametric_curve_applied,
        "parametric gate agrees");
    expect(
        outcome.info.point_curve_applied == cpu.info.point_curve_applied,
        "point curve gate agrees");
    expect(outcome.info.color_mixer_applied == cpu.info.color_mixer_applied, "mixer gate agrees");
    expect(
        outcome.info.color_grading_applied == cpu.info.color_grading_applied,
        "grading gate agrees");
    expect(
        outcome.info.primary_calibration_applied == cpu.info.primary_calibration_applied,
        "primary gate agrees");
    // 측정 밴드는 **정확히 같을 수 없습니다.** 측정은 기본 톤까지 끝난 이미지의 백분위인데,
    // 그 이미지가 이미 1e-06 급으로 다르므로 정렬 순서가 한 칸 밀릴 수 있습니다.
    // 밴드가 크게 벌어지면 커브가 다른 자리에서 걸린 것이니 그것만 봅니다.
    const auto& gpu_bands = outcome.info.measurement.info.bands;
    const auto& cpu_bands = cpu.info.measurement.info.bands;
    const float band_delta = std::max(
        std::abs(gpu_bands.shadow_low - cpu_bands.shadow_low),
        std::max(
            std::abs(gpu_bands.dark_high - cpu_bands.dark_high),
            std::max(
                std::abs(gpu_bands.light_high - cpu_bands.light_high),
                std::abs(gpu_bands.highlight_high - cpu_bands.highlight_high))));
    if (band_delta > 1.0e-3F) {
        std::cerr << "FAIL: measured band delta " << band_delta << '\n';
        ++failures;
    } else {
        std::cout << "[gpu] pipeline tone band delta " << band_delta << '\n';
    }
}

void tone_no_change_is_a_pass_through() {
    // 아무것도 안 움직이면 CPU 는 원본 그대로 내보냅니다. GPU 도 올리지조차 않아야 합니다.
    const WorkingToneAdjustParameters parameters{};
    WorkingImage image = make_image();
    const std::vector<Rgba32F> before = image.pixels;
    const auto outcome = GpuAccelerator::shared().apply_working_tone_adjustments(
        GpuUsePolicy::allowed, image, parameters, {});
    if (!GpuAccelerator::shared().available()) {
        return;
    }
    expect(outcome.handled, "a no-change request is still handled");
    expect(worst_delta(before, image.pixels) == 0.0F, "a no-change request copies nothing");
}

void denoise_path_runs_on_gpu() {
    FilmScanDenoiseParameters parameters{};
    parameters.strength = 0.6F;
    parameters.film_profile = negaflow::imaging::FilmScanDenoiseFilmProfile::color_negative;

    // ① `cpu_only` 는 손대지 않습니다.
    {
        WorkingImage image = make_image();
        const std::vector<Rgba32F> before = image.pixels;
        const auto outcome = GpuAccelerator::shared().apply_film_scan_denoise(
            GpuUsePolicy::cpu_only, image, parameters);
        expect(!outcome.handled, "cpu_only must not use the GPU for denoise");
        expect(worst_delta(before, image.pixels) == 0.0F, "cpu_only leaves denoise pixels alone");
    }

    const auto cpu =
        negaflow::imaging::apply_film_scan_denoise(make_image(), parameters);
    if (cpu.status != negaflow::imaging::FilmScanDenoiseStatus::ok || !cpu.info.applied) {
        expect(false, "the CPU denoise path must succeed");
        return;
    }

    WorkingImage image = make_image();
    const auto outcome = GpuAccelerator::shared().apply_film_scan_denoise(
        GpuUsePolicy::allowed, image, parameters);
    if (!GpuAccelerator::shared().available()) {
        return;
    }
    expect(outcome.handled, "the denoise path must actually run on the GPU");
    if (!outcome.handled) {
        return;
    }
    expect(outcome.info.applied == cpu.info.applied, "the denoise applied flag agrees");
    // 타일 수가 같아야 합니다 — 다르면 GPU 가 CPU 와 다르게 나눈 것이고, 그 순간 값이 갈립니다.
    expect(
        outcome.info.tiles_processed == cpu.info.tiles_processed,
        "the GPU must split into the same tiles as the CPU");

    const float worst = worst_delta(cpu.image.pixels, image.pixels);
    if (worst > denoise_tolerance) {
        std::cerr << "FAIL: denoise gpu/cpu max delta " << worst << '\n';
        ++failures;
    } else {
        std::cout << "[gpu] pipeline denoise max delta " << worst << '\n';
    }
}

void invert_then_tone_is_one_host_round_trip() {
    // macOS CIImage 는 반전·톤을 GPU 에 두고 마지막에 한 번만 평가합니다.
    // 스코프 안에서 invert + tone 을 부르면 풀해상도 올리기/내리기가 한 번씩이어야 합니다.
    if (!GpuAccelerator::shared().available()) {
        return;
    }
    negaflow::pipeline::install_gpu_kernel_accelerator();

    WorkingImage source = make_image();
    WorkingImage cpu = source;
    const auto response = negaflow::core::color_negative_print_response();
    const negaflow::core::NegativeInversionParameters invert_parameters{
        {0.1910F, 0.0940F, 0.0711F}, {1.0F, 1.0F, 1.0F}};
    const negaflow::core::ConstImageView cpu_in{
        cpu.pixels.data(), cpu.pixels.size(), cpu.width, cpu.height, cpu.stride_pixels};
    const negaflow::core::ImageView cpu_out{
        cpu.pixels.data(), cpu.pixels.size(), cpu.width, cpu.height, cpu.stride_pixels};
    expect(
        negaflow::core::apply_negative_inversion(
            cpu_in, cpu_out, invert_parameters, response) ==
            negaflow::core::KernelStatus::ok,
        "CPU invert must succeed");
    WorkingToneAdjustParameters tone{};
    tone.exposure_stops = 0.30F;
    tone.basic.contrast = 0.20F;
    const auto cpu_tone = negaflow::imaging::apply_working_tone_adjustments(std::move(cpu), tone);
    expect(
        cpu_tone.status == negaflow::imaging::WorkingToneAdjustStatus::ok,
        "CPU tone after invert must succeed");

    WorkingImage gpu = source;
    const float dmin[3] = {0.1910F, 0.0940F, 0.0711F};
    const float dmax[3] = {1.0F, 1.0F, 1.0F};
    const float response_values[4] = {
        response.y_ceiling, response.amplitude, response.rate, response.shape};
    negaflow::pipeline::reset_gpu_host_transfer_stats();
    {
        negaflow::imaging::ApproximateAcceleratorScope approximate{};
        negaflow::pipeline::GpuResidentScope resident{};
        expect(
            GpuAccelerator::shared().apply_negative_inversion(
                reinterpret_cast<float*>(gpu.pixels.data()),
                gpu.width,
                gpu.height,
                gpu.stride_pixels,
                dmin,
                dmax,
                response_values),
            "GPU invert must handle the resident request");
        const auto outcome = GpuAccelerator::shared().apply_working_tone_adjustments(
            GpuUsePolicy::allowed, gpu, tone, {});
        expect(outcome.handled, "GPU tone must run on the resident image");
    }
    const auto stats = negaflow::pipeline::gpu_host_transfer_stats();
    const auto full = static_cast<std::uint64_t>(width) * height;
    expect(stats.uploads == 1U, "resident invert+tone uploads once");
    expect(stats.uploaded_pixels == full, "the one upload is the full working image");
    expect(stats.downloads == 1U, "resident invert+tone downloads once");
    expect(stats.downloaded_pixels == full, "the one download is the full working image");
    expect(
        stats.downloaded_bytes == full * 16ULL,
        "the invert+tone scope download is still float32");

    const float worst = worst_delta(cpu_tone.image.pixels, gpu.pixels);
    if (worst > tone_tolerance) {
        std::cerr << "FAIL: resident invert+tone gpu/cpu max delta " << worst << '\n';
        ++failures;
    } else {
        std::cout << "[gpu] resident invert+tone max delta " << worst
                  << " uploads=" << stats.uploads << " downloads=" << stats.downloads << '\n';
    }
}

void invert_then_tone_preview_is_one_bgra_download() {
    // macOS `renderDisplayCGImage` 는 `createCGImage(..., format: .RGBA8)` 한 번입니다.
    // 상주 사슬의 마지막 회수는 float32 가 아니라 BGRA8 이어야 합니다.
    if (!GpuAccelerator::shared().available()) {
        return;
    }
    negaflow::pipeline::install_gpu_kernel_accelerator();

    WorkingImage source = make_image();
    WorkingImage cpu = source;
    const auto response = negaflow::core::color_negative_print_response();
    const negaflow::core::NegativeInversionParameters invert_parameters{
        {0.1910F, 0.0940F, 0.0711F}, {1.0F, 1.0F, 1.0F}};
    const negaflow::core::ConstImageView cpu_in{
        cpu.pixels.data(), cpu.pixels.size(), cpu.width, cpu.height, cpu.stride_pixels};
    const negaflow::core::ImageView cpu_out{
        cpu.pixels.data(), cpu.pixels.size(), cpu.width, cpu.height, cpu.stride_pixels};
    expect(
        negaflow::core::apply_negative_inversion(
            cpu_in, cpu_out, invert_parameters, response) ==
            negaflow::core::KernelStatus::ok,
        "CPU invert for preview encode must succeed");
    WorkingToneAdjustParameters tone{};
    tone.exposure_stops = 0.30F;
    tone.basic.contrast = 0.20F;
    const auto cpu_tone = negaflow::imaging::apply_working_tone_adjustments(std::move(cpu), tone);
    expect(
        cpu_tone.status == negaflow::imaging::WorkingToneAdjustStatus::ok,
        "CPU tone for preview encode must succeed");

    std::vector<std::uint8_t> cpu_bgra(
        static_cast<std::size_t>(width) * height * 4U, 0U);
    negaflow::pipeline::develop_export_detail::PreviewTarget cpu_target{
        width, height, cpu_bgra.data(), cpu_bgra.size(), {}, false};
    negaflow::pipeline::DevelopExportOutcome cpu_preview{};
    cpu_preview = negaflow::pipeline::develop_export_detail::write_preview(
        cpu_tone.image, cpu_target, cpu_preview);
    expect(cpu_preview.succeeded, "CPU write_preview must succeed");

    WorkingImage gpu = source;
    const float dmin[3] = {0.1910F, 0.0940F, 0.0711F};
    const float dmax[3] = {1.0F, 1.0F, 1.0F};
    const float response_values[4] = {
        response.y_ceiling, response.amplitude, response.rate, response.shape};
    std::vector<std::uint8_t> gpu_bgra(
        static_cast<std::size_t>(width) * height * 4U, 0U);
    negaflow::pipeline::reset_gpu_host_transfer_stats();
    {
        negaflow::imaging::ApproximateAcceleratorScope approximate{};
        negaflow::pipeline::GpuResidentScope resident{};
        expect(
            GpuAccelerator::shared().apply_negative_inversion(
                reinterpret_cast<float*>(gpu.pixels.data()),
                gpu.width,
                gpu.height,
                gpu.stride_pixels,
                dmin,
                dmax,
                response_values),
            "GPU invert must handle the resident preview request");
        const auto outcome = GpuAccelerator::shared().apply_working_tone_adjustments(
            GpuUsePolicy::allowed, gpu, tone, {});
        expect(outcome.handled, "GPU tone must run on the resident preview image");
        negaflow::pipeline::develop_export_detail::PreviewTarget gpu_target{
            width, height, gpu_bgra.data(), gpu_bgra.size(), {}, false};
        negaflow::pipeline::DevelopExportOutcome gpu_preview{};
        gpu_preview = negaflow::pipeline::develop_export_detail::write_preview(
            gpu, gpu_target, gpu_preview);
        expect(gpu_preview.succeeded, "GPU write_preview must encode BGRA8");
    }
    const auto stats = negaflow::pipeline::gpu_host_transfer_stats();
    const auto full = static_cast<std::uint64_t>(width) * height;
    expect(stats.uploads == 1U, "resident invert+tone+encode uploads once");
    expect(stats.uploaded_pixels == full, "the one upload is the full working image");
    expect(stats.downloads == 1U, "resident invert+tone+encode downloads once");
    expect(stats.downloaded_pixels == full, "the one download is the preview image");
    expect(
        stats.downloaded_bytes == full * 4ULL,
        "the last download is BGRA8, not float32");

    int worst = 0;
    for (std::size_t index = 0U; index < cpu_bgra.size(); ++index) {
        const int delta = std::abs(
            static_cast<int>(cpu_bgra[index]) - static_cast<int>(gpu_bgra[index]));
        worst = std::max(worst, delta);
    }
    if (worst > 1) {
        std::cerr << "FAIL: preview BGRA gpu/cpu max code delta " << worst << '\n';
        ++failures;
    } else {
        std::cout << "[gpu] resident invert+tone BGRA max code delta " << worst
                  << " uploads=" << stats.uploads << " downloads=" << stats.downloads
                  << " downloaded_bytes=" << stats.downloaded_bytes << '\n';
    }
}

// 자르기가 걸린 사진은 발행 커널이 **읽는 자리를 바꿔** 변환을 함께 처리합니다
// (`preview_display_encode.hlsl` `SourceCoordinate`). 그 식이 CPU
// `apply_image_transform` 과 어긋나면 **엉뚱한 자리가 잘린 사진**이 나옵니다.
// 호스트 쪽 식은 `image_transform_tests` 가 고정하고, 여기서는 **셰이더**가 같은
// 자리를 읽는지를 봅니다.
void deferred_transform_preview_matches_cpu() {
    if (!GpuAccelerator::shared().available()) {
        return;
    }
    negaflow::imaging::ImageTransformParameters parameters{};
    parameters.rotation = negaflow::imaging::ImageRotation::degrees_90;
    parameters.flip_horizontal = true;
    parameters.has_crop = true;
    parameters.crop = {0.2, 0.15, 0.55, 0.6};

    negaflow::imaging::ImageTransformGather gather{};
    expect(
        negaflow::imaging::plan_image_transform_gather(
            parameters, width, height, gather),
        "the fixture transform must plan a gather");

    // CPU 기준: 변환을 걸고 평소 발행 경로로 갑니다.
    const auto applied =
        negaflow::imaging::apply_image_transform(make_image(), parameters);
    expect(
        applied.status == negaflow::imaging::ImageTransformStatus::ok,
        "the CPU transform must succeed");
    std::vector<std::uint8_t> cpu_bgra(
        static_cast<std::size_t>(gather.output_width) * gather.output_height * 4U, 0U);
    negaflow::pipeline::develop_export_detail::PreviewTarget cpu_target{
        gather.output_width, gather.output_height,
        cpu_bgra.data(), cpu_bgra.size(), {}, false};
    negaflow::pipeline::DevelopExportOutcome cpu_preview{};
    cpu_preview = negaflow::pipeline::develop_export_detail::write_preview(
        applied.image, cpu_target, cpu_preview);
    expect(cpu_preview.succeeded, "CPU deferred-transform reference must succeed");

    // GPU 기준: 변환을 걸지 않은 상주 화상에 gather 를 넘깁니다.
    WorkingImage resident_image = make_image();
    std::vector<std::uint8_t> gpu_bgra(cpu_bgra.size(), 0U);
    {
        negaflow::imaging::ApproximateAcceleratorScope approximate{};
        negaflow::pipeline::GpuResidentScope resident{};
        WorkingToneAdjustParameters tone{};
        tone.exposure_stops = 0.0F;
        // 상주로 묶으려면 GPU 커널이 한 번 돌아야 합니다. 항등 톤은 올리지도 않으므로
        // 아주 작은 노출을 걸어 실제로 상주 이미지를 만듭니다.
        tone.basic.contrast = 0.05F;
        const auto outcome = GpuAccelerator::shared().apply_working_tone_adjustments(
            GpuUsePolicy::allowed, resident_image, tone, {});
        expect(outcome.handled, "the fixture needs a resident GPU image");
        if (!outcome.handled) {
            return;
        }
        negaflow::pipeline::develop_export_detail::PreviewTarget gpu_target{
            gather.output_width, gather.output_height,
            gpu_bgra.data(), gpu_bgra.size(), {}, false};
        negaflow::pipeline::DevelopExportOutcome gpu_preview{};
        gpu_preview = negaflow::pipeline::develop_export_detail::write_preview(
            resident_image, gpu_target, gpu_preview, &gather);
        expect(
            gpu_preview.succeeded &&
                gpu_preview.image_width == gather.output_width &&
                gpu_preview.image_height == gather.output_height,
            "the deferred-transform publish must report the transformed extent");
    }

    // CPU 기준은 톤을 안 걸었으므로 화소 값 자체는 다릅니다. 여기서 보는 것은
    // **어느 자리를 읽었는가** 이므로, 같은 톤을 건 CPU 판으로 다시 맞춥니다.
    WorkingImage toned = make_image();
    WorkingToneAdjustParameters tone{};
    tone.basic.contrast = 0.05F;
    auto cpu_toned = negaflow::imaging::apply_working_tone_adjustments(
        std::move(toned), tone);
    expect(
        cpu_toned.status == negaflow::imaging::WorkingToneAdjustStatus::ok,
        "the CPU tone reference must succeed");
    const auto cpu_applied =
        negaflow::imaging::apply_image_transform(std::move(cpu_toned.image), parameters);
    negaflow::pipeline::develop_export_detail::PreviewTarget ref_target{
        gather.output_width, gather.output_height,
        cpu_bgra.data(), cpu_bgra.size(), {}, false};
    negaflow::pipeline::DevelopExportOutcome ref_preview{};
    ref_preview = negaflow::pipeline::develop_export_detail::write_preview(
        cpu_applied.image, ref_target, ref_preview);
    expect(ref_preview.succeeded, "the CPU reference publish must succeed");

    int worst = 0;
    for (std::size_t index = 0U; index < cpu_bgra.size(); ++index) {
        worst = std::max(
            worst,
            std::abs(static_cast<int>(cpu_bgra[index]) -
                     static_cast<int>(gpu_bgra[index])));
    }
    if (worst > 1) {
        std::cerr << "FAIL: deferred transform BGRA max code delta " << worst << '\n';
        ++failures;
    } else {
        std::cout << "[gpu] deferred transform BGRA max code delta " << worst
                  << " extent " << gather.output_width << "x" << gather.output_height
                  << '\n';
    }
}

void denoise_below_threshold_is_a_pass_through() {
    FilmScanDenoiseParameters parameters{};
    parameters.strength = 0.0005F; // 임계 1e-3 아래.
    WorkingImage image = make_image();
    const std::vector<Rgba32F> before = image.pixels;
    const auto outcome = GpuAccelerator::shared().apply_film_scan_denoise(
        GpuUsePolicy::allowed, image, parameters);
    if (!GpuAccelerator::shared().available()) {
        return;
    }
    expect(outcome.handled, "a below-threshold request is still handled");
    expect(!outcome.info.applied, "a below-threshold request is not applied");
    expect(worst_delta(before, image.pixels) == 0.0F, "a below-threshold request copies nothing");
}

// 자동 레벨 · 자동 중성 균형이 **파이프라인에서 GPU 로 도는지**, 그리고 그 결과가 CPU 판과
// 눈에 안 보일 만큼 같은지입니다.
//
// 이 시험이 있어야 하는 이유 — 이 단계가 GPU 를 못 타면 `grade.cpp` 가 `flush_resident()` 로
// 화소를 내리고, 그 뒤 톤·필름룩·마무리·발행이 **전부 호스트**로 돌아갑니다. 커널이
// 조용히 빠지면 "왜 다시 느려졌는지" 를 아무도 모릅니다.
void scene_correction_path_runs_on_gpu() {
    negaflow::imaging::SceneCorrectionParameters parameters{};
    parameters.auto_levels = true;
    parameters.auto_neutral_balance = true;
    parameters.negative_source = true;

    // ① `cpu_only` 는 손대지 않습니다.
    {
        WorkingImage image = make_image();
        const std::vector<Rgba32F> before = image.pixels;
        negaflow::imaging::SceneCorrectionInfo info{};
        expect(
            !GpuAccelerator::shared().apply_scene_correction(
                GpuUsePolicy::cpu_only, image, parameters, info),
            "cpu_only must not use the GPU for scene correction");
        expect(
            worst_delta(before, image.pixels) == 0.0F,
            "cpu_only scene correction must leave pixels alone");
    }

    // CPU 기준값.
    WorkingImage reference = make_image();
    negaflow::imaging::SceneCorrectionInfo cpu_info{};
    const negaflow::core::KernelStatus cpu_status =
        negaflow::imaging::apply_scene_correction(
            {
                reference.pixels.data(),
                reference.pixels.size(),
                reference.width,
                reference.height,
                reference.stride_pixels,
            },
            parameters,
            cpu_info);
    expect(
        cpu_status == negaflow::core::KernelStatus::ok,
        "the CPU scene correction path must succeed");

    WorkingImage image = make_image();
    negaflow::imaging::SceneCorrectionInfo gpu_info{};
    const bool handled = GpuAccelerator::shared().apply_scene_correction(
        GpuUsePolicy::allowed, image, parameters, gpu_info);
    if (!GpuAccelerator::shared().available()) {
        return;
    }
    expect(handled, "the scene correction path must run on the GPU");
    if (!handled) {
        return;
    }
    // 적용 여부 판정은 CPU 의 공개 함수 한 벌을 두 경로가 같이 씁니다 — 어긋나면 규칙이
    // 두 벌이 됐다는 뜻입니다.
    expect(
        gpu_info.auto_levels_applied == cpu_info.auto_levels_applied,
        "GPU and CPU must agree on whether auto levels applied");
    expect(
        gpu_info.neutral_balance_applied == cpu_info.neutral_balance_applied,
        "GPU and CPU must agree on whether neutral balance applied");
    // 표본 누적이 CPU 는 double, GPU 는 float 입니다. 백분위·중앙값을 지나면 계수 차이는
    // 아주 작지만 바이트 일치는 아닙니다.
    const float worst = worst_delta(reference.pixels, image.pixels);
    if (worst > scene_tolerance) {
        std::cerr << "FAIL: scene correction gpu/cpu max delta " << worst << '\n';
        ++failures;
    } else {
        std::cout << "[gpu] pipeline scene correction max delta " << worst
                  << " levels=" << (gpu_info.auto_levels_applied ? 1 : 0)
                  << " balance=" << (gpu_info.neutral_balance_applied ? 1 : 0) << '\n';
    }
}

// 위 시험의 합성 화상은 중앙값 게이트에 걸려 **중성 균형이 적용되지 않습니다.** 그러면
// 32칸 큐브 커널이 한 번도 안 돕니다. 색이 확실히 치우친 화상으로 그 갈래를 따로 덮습니다.
void scene_neutral_balance_runs_on_gpu() {
    negaflow::imaging::SceneCorrectionParameters parameters{};
    parameters.auto_neutral_balance = true;
    parameters.negative_source = true;

    WorkingImage reference = make_cast_image();
    negaflow::imaging::SceneCorrectionInfo cpu_info{};
    expect(
        negaflow::imaging::apply_scene_correction(
            {
                reference.pixels.data(),
                reference.pixels.size(),
                reference.width,
                reference.height,
                reference.stride_pixels,
            },
            parameters,
            cpu_info) == negaflow::core::KernelStatus::ok,
        "the CPU neutral balance path must succeed");
    expect(
        cpu_info.neutral_balance_applied,
        "the cast fixture must actually trigger neutral balance on the CPU");

    WorkingImage image = make_cast_image();
    negaflow::imaging::SceneCorrectionInfo gpu_info{};
    const bool handled = GpuAccelerator::shared().apply_scene_correction(
        GpuUsePolicy::allowed, image, parameters, gpu_info);
    if (!GpuAccelerator::shared().available()) {
        return;
    }
    expect(handled, "the neutral balance path must run on the GPU");
    expect(
        gpu_info.neutral_balance_applied == cpu_info.neutral_balance_applied,
        "GPU and CPU must agree on whether neutral balance applied");
    if (!handled) {
        return;
    }
    const float worst = worst_delta(reference.pixels, image.pixels);
    if (worst > scene_tolerance) {
        std::cerr << "FAIL: neutral balance gpu/cpu max delta " << worst << '\n';
        ++failures;
    } else {
        std::cout << "[gpu] pipeline neutral balance max delta " << worst << '\n';
    }
}

} // namespace

int main() {
    std::cout << "[gpu] accelerator: "
              << (GpuAccelerator::shared().available()
                      ? GpuAccelerator::shared().adapter_description()
                      : "unavailable")
              << '\n';
    tone_path_runs_on_gpu();
    tone_no_change_is_a_pass_through();
    invert_then_tone_is_one_host_round_trip();
    invert_then_tone_preview_is_one_bgra_download();
    denoise_path_runs_on_gpu();
    denoise_below_threshold_is_a_pass_through();
    scene_correction_path_runs_on_gpu();
    scene_neutral_balance_runs_on_gpu();
    deferred_transform_preview_matches_cpu();

    if (failures != 0) {
        std::cerr << failures << " gpu accelerator check(s) failed\n";
        return 1;
    }
    std::cout << "gpu accelerator checks passed\n";
    return 0;
}
