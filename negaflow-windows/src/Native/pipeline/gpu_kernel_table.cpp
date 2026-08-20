#include "negaflow/pipeline/gpu_accelerator.h"

// `imaging` 안쪽 커널을 GPU 로 보내는 **함수 표**입니다. 클래스 본체(`gpu_accelerator.cpp`)와
// 나눠 둔 이유는 둘이 하는 일이 다르기 때문입니다 — 저쪽은 장치·자물쇠·텍스처를 들고
// 실제 디스패치를 하고, 여기는 **무엇을 표에 걸지**를 정합니다. 정책이 바뀌는 것은 늘 이쪽입니다.

#include <cstdlib>
#include <mutex>

namespace negaflow::pipeline {

namespace {

// `imaging` 안쪽 커널을 GPU 로 보내는 표입니다. `imaging` 은 `gpu` 를 링크할 수 없으므로
// (링크하면 순환) 함수 표만 알고, 둘 다 링크하는 이 층이 채웁니다.
//
// ☠️ **형태학만 넣습니다.** 창 안에서 하나를 고르는 일이라 부동소수 산술이 없고, 창과
//    가장자리 처리가 같으면 고른 값도 같습니다 — 시험이 전 반경에서 **비트 단위 일치**로
//    고정해 두었습니다. 그래서 내보내기·골든 경로에서도 켭니다.
//    곱셈·덧셈이 들어가는 커널은 여기 넣지 마십시오. `KernelAccelerator` 헤더의
//    "근사한 것" 칸과 `ApproximateAcceleratorScope` 를 쓰십시오.

[[nodiscard]] bool run_morphology(
    const float* const source,
    float* const destination,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t radius,
    const imaging::MorphologyKind kind) noexcept {
    GpuAccelerator& accelerator = GpuAccelerator::shared();
    if (!accelerator.available()) {
        return false;
    }
    return accelerator.apply_morphology_plane(source, destination, width, height, radius, kind);
}

bool accelerate_opening(
    const float* const source,
    float* const destination,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t radius) noexcept {
    return run_morphology(
        source, destination, width, height, radius, imaging::MorphologyKind::opening);
}

bool accelerate_closing(
    const float* const source,
    float* const destination,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t radius) noexcept {
    return run_morphology(
        source, destination, width, height, radius, imaging::MorphologyKind::closing);
}

bool accelerate_bipolar_top_hat(
    const float* const source,
    float* const destination,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t radius) noexcept {
    return run_morphology(
        source, destination, width, height, radius, imaging::MorphologyKind::bipolar_top_hat);
}

bool accelerate_morphology_rgb(
    const float* const red,
    const float* const green,
    const float* const blue,
    float* const out_red,
    float* const out_green,
    float* const out_blue,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t radius,
    const imaging::MorphologyKind kind) noexcept {
    GpuAccelerator& accelerator = GpuAccelerator::shared();
    if (!accelerator.available()) {
        return false;
    }
    return accelerator.apply_morphology_rgb(
        red, green, blue, out_red, out_green, out_blue, width, height, radius, kind);
}

bool accelerate_opening_rgb(
    const float* const red,
    const float* const green,
    const float* const blue,
    float* const out_red,
    float* const out_green,
    float* const out_blue,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t radius) noexcept {
    return accelerate_morphology_rgb(
        red, green, blue, out_red, out_green, out_blue, width, height, radius,
        imaging::MorphologyKind::opening);
}

bool accelerate_closing_rgb(
    const float* const red,
    const float* const green,
    const float* const blue,
    float* const out_red,
    float* const out_green,
    float* const out_blue,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t radius) noexcept {
    return accelerate_morphology_rgb(
        red, green, blue, out_red, out_green, out_blue, width, height, radius,
        imaging::MorphologyKind::closing);
}

bool accelerate_bipolar_top_hat_rgb(
    const float* const red,
    const float* const green,
    const float* const blue,
    float* const out_red,
    float* const out_green,
    float* const out_blue,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t radius) noexcept {
    GpuAccelerator& accelerator = GpuAccelerator::shared();
    if (!accelerator.available()) {
        return false;
    }
    return accelerator.apply_morphology_bipolar_top_hat_rgb(
        red, green, blue, out_red, out_green, out_blue, width, height, radius);
}

// 네거티브 반전입니다. 형태학과 달리 **근사**이고(곱셈·초월함수), 현상 한 번에 **한 번만**
// 불리므로 왕복이 1회입니다 — 형태학이 느려진 두 이유(수십 번 왕복·직렬화) 중 하나가 없습니다.
// 실측으로 프리뷰 856 ms 중 353 ms(41%)가 이 단계입니다.
bool accelerate_negative_inversion(
    float* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_pixels,
    const float* const dmin,
    const float* const dmax_normalized,
    const float* const response) noexcept {
    GpuAccelerator& accelerator = GpuAccelerator::shared();
    if (!accelerator.available()) {
        return false;
    }
    return accelerator.apply_negative_inversion(
        pixels, width, height, stride_pixels, dmin, dmax_normalized, response);
}

// 디지털 필름 룩의 재료 커널 둘입니다. 반전과 같은 이유로 왕복이 **한 번씩**이고
// (사슬에서 한 번만 불립니다) 둘 다 근사이므로 스코프 안에서만 돕니다.
bool accelerate_digital_halation(
    float* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_pixels,
    const double* const scatter_strength,
    const double* const halation_strength,
    const double radius_ratio,
    const double strength) noexcept {
    GpuAccelerator& accelerator = GpuAccelerator::shared();
    if (!accelerator.available()) {
        return false;
    }
    return accelerator.apply_digital_halation(
        pixels, width, height, stride_pixels, scatter_strength, halation_strength,
        radius_ratio, strength);
}

bool accelerate_digital_film_grain(
    float* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_pixels,
    const float amplitude,
    const float chroma_ratio,
    const float size) noexcept {
    GpuAccelerator& accelerator = GpuAccelerator::shared();
    if (!accelerator.available()) {
        return false;
    }
    return accelerator.apply_digital_film_grain(
        pixels, width, height, stride_pixels, amplitude, chroma_ratio, size);
}

bool accelerate_digital_film_color_preset(
    float* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_pixels,
    const imaging::DigitalFilmColorPreset* const preset,
    const float strength) noexcept {
    GpuAccelerator& accelerator = GpuAccelerator::shared();
    if (!accelerator.available()) {
        return false;
    }
    return accelerator.apply_digital_film_color_preset(
        pixels, width, height, stride_pixels, preset, strength);
}

bool accelerate_film_emulation_cube(
    float* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_pixels,
    const imaging::FilmEmulationColorCube* const cube) noexcept {
    GpuAccelerator& accelerator = GpuAccelerator::shared();
    if (!accelerator.available()) {
        return false;
    }
    return accelerator.apply_film_emulation_cube(pixels, width, height, stride_pixels, cube);
}

bool accelerate_film_emulation_acutance(
    float* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_pixels,
    const imaging::FilmEmulationAcutanceSetup* const setup) noexcept {
    GpuAccelerator& accelerator = GpuAccelerator::shared();
    if (!accelerator.available()) {
        return false;
    }
    return accelerator.apply_film_emulation_acutance(
        pixels, width, height, stride_pixels, setup);
}

bool accelerate_digital_film_look(
    float* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_pixels,
    const imaging::DigitalFilmLookPlan* const plan,
    imaging::DigitalFilmLookApplied* const applied) noexcept {
    GpuAccelerator& accelerator = GpuAccelerator::shared();
    if (!accelerator.available()) {
        return false;
    }
    return accelerator.apply_digital_film_look(
        pixels, width, height, stride_pixels, plan, applied);
}

bool accelerate_digital_bw_film_look(
    float* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_pixels,
    const imaging::DigitalBwFilmLookPlan* const plan,
    imaging::DigitalBwFilmLookApplied* const applied) noexcept {
    GpuAccelerator& accelerator = GpuAccelerator::shared();
    if (!accelerator.available()) {
        return false;
    }
    return accelerator.apply_digital_bw_film_look(
        pixels, width, height, stride_pixels, plan, applied);
}

bool accelerate_muted_scene_vibrance(
    float* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_pixels,
    const float amount) noexcept {
    GpuAccelerator& accelerator = GpuAccelerator::shared();
    if (!accelerator.available()) {
        return false;
    }
    return accelerator.apply_muted_scene_vibrance(
        pixels, width, height, stride_pixels, amount);
}

bool accelerate_color_model(
    float* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_pixels,
    const imaging::ColorModelParameters* const parameters) noexcept {
    GpuAccelerator& accelerator = GpuAccelerator::shared();
    if (!accelerator.available()) {
        return false;
    }
    return accelerator.apply_color_model(pixels, width, height, stride_pixels, parameters);
}

bool accelerate_scanner_target_grade(
    float* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_pixels,
    const imaging::ScannerTargetGradeSetup* const setup) noexcept {
    GpuAccelerator& accelerator = GpuAccelerator::shared();
    if (!accelerator.available()) {
        return false;
    }
    return accelerator.apply_scanner_target_grade(
        pixels, width, height, stride_pixels, setup);
}

bool accelerate_noritsu_texture(
    float* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_pixels,
    const imaging::ScannerTargetTextureSetup* const setup) noexcept {
    GpuAccelerator& accelerator = GpuAccelerator::shared();
    if (!accelerator.available()) {
        return false;
    }
    return accelerator.apply_noritsu_texture(
        pixels, width, height, stride_pixels, setup);
}

// 2026-08-19 실측(5088×3401 프리뷰, grain 0.40, RTX 4060 Ti):
//   texture 단계 CPU 26.84 ms / GPU 69.52 ms. 커널은 맞지만 왕복이 집니다.
//   기본은 끕니다. `NEGA_GPU_TEXTURE_GRAIN=1` 로만 켭니다.
[[nodiscard]] bool texture_grain_enabled_by_environment() noexcept {
    char value[8]{};
    std::size_t length = 0U;
    if (getenv_s(&length, value, sizeof(value), "NEGA_GPU_TEXTURE_GRAIN") != 0 ||
        length == 0U) {
        return false;
    }
    return value[0] == 49;  // 49 == '1'
}

bool accelerate_texture_grain(
    float* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_pixels,
    const float amount) noexcept {
    if (!texture_grain_enabled_by_environment()) {
        return false;
    }
    GpuAccelerator& accelerator = GpuAccelerator::shared();
    if (!accelerator.available()) {
        return false;
    }
    return accelerator.apply_texture_grain(pixels, width, height, stride_pixels, amount);
}

bool accelerate_channel_clipping_overlay(
    const float* const source,
    float* const destination,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t source_stride_pixels,
    const std::uint32_t destination_stride_pixels) noexcept {
    GpuAccelerator& accelerator = GpuAccelerator::shared();
    if (!accelerator.available()) {
        return false;
    }
    return accelerator.apply_channel_clipping_overlay(
        source,
        destination,
        width,
        height,
        source_stride_pixels,
        destination_stride_pixels);
}

// 2026-08-19 실측(5088×3401 전체 프레임, RTX 4060 Ti, x2 마지막 회차):
//   CPU 25.109 ms / GPU 33.397 ms. 리덕션은 맞지만 업로드가 집니다.
//   기본은 끕니다. `NEGA_GPU_AREA_AVERAGE=1` 로만 켭니다.
[[nodiscard]] bool area_average_enabled_by_environment() noexcept {
    char value[8]{};
    std::size_t length = 0U;
    if (getenv_s(&length, value, sizeof(value), "NEGA_GPU_AREA_AVERAGE") != 0 ||
        length == 0U) {
        return false;
    }
    return value[0] == 49;  // 49 == '1'
}

bool accelerate_area_average(
    const float* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_pixels,
    const std::uint32_t origin_x,
    const std::uint32_t origin_y,
    const std::uint32_t extent_width,
    const std::uint32_t extent_height,
    float mean[4],
    std::uint64_t* const count) noexcept {
    if (!area_average_enabled_by_environment()) {
        return false;
    }
    GpuAccelerator& accelerator = GpuAccelerator::shared();
    if (!accelerator.available() || count == nullptr) {
        return false;
    }
    return accelerator.apply_area_average(
        pixels,
        width,
        height,
        stride_pixels,
        origin_x,
        origin_y,
        extent_width,
        extent_height,
        mean,
        count);
}

// 2026-08-19 실측(5088×3401 프리뷰 x2 마지막): 전체 617.69 → 629.15 ms. 이득 없음.
// 기본은 끕니다. `NEGA_GPU_MIP_HALVE=1` 로만 켭니다. GenerateMips 는 쓰지 않습니다.
[[nodiscard]] bool mip_halve_enabled_by_environment() noexcept {
    char value[8]{};
    std::size_t length = 0U;
    if (getenv_s(&length, value, sizeof(value), "NEGA_GPU_MIP_HALVE") != 0 ||
        length == 0U) {
        return false;
    }
    return value[0] == 49;  // 49 == '1'
}

bool accelerate_mip_halve_levels(
    const float* const source,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_pixels,
    const int wanted_levels,
    float* const destination,
    const std::uint32_t destination_capacity,
    std::uint32_t* const out_width,
    std::uint32_t* const out_height) noexcept {
    GpuAccelerator& accelerator = GpuAccelerator::shared();
    if (!accelerator.available() || out_width == nullptr || out_height == nullptr) {
        return false;
    }
    // 상주가 아니면 올리기가 비싸 기본 끔(`NEGA_GPU_MIP_HALVE=1`).
    // 상주면 올리기가 없어서 켭니다 — 호스트가 낡은 채로 CPU 축소를 하면 안 됩니다.
    if (!accelerator.has_resident_image(source, width, height) &&
        !mip_halve_enabled_by_environment()) {
        return false;
    }
    return accelerator.apply_mip_halve_levels(
        source,
        width,
        height,
        stride_pixels,
        wanted_levels,
        destination,
        destination_capacity,
        out_width,
        out_height);
}

bool accelerate_resident_finite(
    const float* const pixels,
    const std::uint32_t width,
    const std::uint32_t height,
    const std::uint32_t stride_pixels,
    bool* const all_finite) noexcept {
    GpuAccelerator& accelerator = GpuAccelerator::shared();
    if (!accelerator.available()) {
        return false;
    }
    return accelerator.check_resident_finite(
        pixels, width, height, stride_pixels, all_finite);
}

// 프로세스 수명 동안 살아 있어야 합니다 — `install_kernel_accelerator` 는 포인터만 갖습니다.
const imaging::KernelAccelerator kernel_table{
    accelerate_opening,
    accelerate_closing,
    accelerate_bipolar_top_hat,
    accelerate_bipolar_top_hat_rgb,
    accelerate_opening_rgb,
    accelerate_closing_rgb,
    accelerate_scratch_angle_maps,
    accelerate_scratch_angle_stack,
    accelerate_digital_halation,
    accelerate_negative_inversion,
    accelerate_digital_film_grain,
    accelerate_digital_film_color_preset,
    accelerate_film_emulation_cube,
    accelerate_film_emulation_acutance,
    accelerate_digital_film_look,
    accelerate_digital_bw_film_look,
    accelerate_muted_scene_vibrance,
    accelerate_color_model,
    accelerate_scanner_target_grade,
    accelerate_noritsu_texture,
    accelerate_texture_grain,
    accelerate_channel_clipping_overlay,
    accelerate_area_average,
    accelerate_mip_halve_levels,
    accelerate_resident_finite,
};

}  // namespace

namespace {

// 2026-08-19 재측정(5088×3401, RTX 4060 Ti, 전송 경로 개선 뒤, 각 3회):
//
//   | 검출 벽시계 | 중앙값 |
//   |---|---:|
//   | CPU (`NEGA_GPU=0`) | **18,052 ms** |
//   | GPU 형태학(호출마다 왕복) | **15,383 ms** |
//
// 결과는 같습니다(성분 610, 채택 9,331). 전송이 줄어든 뒤에는 호출마다 왕복해도
// CPU 보다 빠릅니다. **기본은 켭니다.** `NEGA_GPU_MORPHOLOGY=0` 으로만 끕니다.
[[nodiscard]] bool morphology_enabled_by_environment() noexcept {
    char value[8]{};
    std::size_t length = 0U;
    if (getenv_s(&length, value, sizeof(value), "NEGA_GPU_MORPHOLOGY") != 0 || length == 0U) {
        return true;
    }
    return value[0] != 48;  // 48 == '0'
}

}  // namespace

void install_gpu_kernel_accelerator() noexcept {
    // 여러 번 불려도 한 번만 겁니다. 검출이 돌 때마다 부르는 자리라 필요합니다.
    static std::once_flag once{};
    std::call_once(once, []() noexcept {
        // 장치가 없으면 표를 걸지 않습니다 — 매 호출 실패보다 아예 안 묻는 편이 쌉니다.
        if (!GpuAccelerator::shared().available()) {
            return;
        }
        // 형태학은 2026-08-19 재측정에서 CPU 보다 빨라 기본으로 켭니다. 끄려면
        //    `NEGA_GPU_MORPHOLOGY=0`. 값은 비트 단위로 같습니다.
        static imaging::KernelAccelerator effective = kernel_table;
        if (!morphology_enabled_by_environment()) {
            effective.opening = nullptr;
            effective.closing = nullptr;
            effective.bipolar_top_hat = nullptr;
            effective.bipolar_top_hat_rgb = nullptr;
            effective.opening_rgb = nullptr;
            effective.closing_rgb = nullptr;
        }
        imaging::install_kernel_accelerator(&effective);
    });
}

}  // namespace negaflow::pipeline
