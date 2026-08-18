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

// 프로세스 수명 동안 살아 있어야 합니다 — `install_kernel_accelerator` 는 포인터만 갖습니다.
const imaging::KernelAccelerator kernel_table{
    accelerate_opening,
    accelerate_closing,
    accelerate_bipolar_top_hat,
    accelerate_digital_halation,
    accelerate_negative_inversion,
    accelerate_digital_film_grain,
};

}  // namespace

namespace {

// ☠️ **기본은 꺼짐입니다. 실측이 더 느렸기 때문입니다.**
//
// 2026-08-18 실측(5100×3408 실제 스캔, RTX 4060 Ti, 각 2회):
//
//   | 검출 | 1회 | 2회 |
//   |---|---:|---:|
//   | CPU (`NEGA_GPU=0`) | **9,312 ms** | **9,104 ms** |
//   | GPU 형태학 | 12,146 ms | 11,462 ms |
//
// 결과는 같습니다(성분 1367개, 채택 16,074 화소 — 비트 단위 일치가 지켜집니다).
// **느려진 이유는 커널이 아니라 구조입니다:**
//
//   1. **평면마다 왕복합니다.** 검출은 타일 12개 × 반경 여러 개로 형태학을 수십 번 부르고,
//      지금은 호출마다 업로드·다운로드를 합니다. 커널이 아무리 빨라도 전송이 지배합니다.
//   2. **직렬화됩니다.** D3D11 즉시 컨텍스트가 스레드 안전하지 않아 GPU 호출이 자물쇠
//      하나를 지납니다. CPU 경로는 워커 4개로 **병렬**인데, GPU 로 바꾸면 그것이 직렬이 됩니다.
//
// 즉 4중 병렬 CPU 작업을 직렬 GPU 작업 + 왕복으로 바꾼 것이라 느려지는 것이 당연합니다.
// **고치는 길은 검출 전체를 GPU 에 머무르게 하는 오케스트레이터**입니다 — 04 3절의
// "단계마다 올렸다 내리면 집니다" 가 여기에도 그대로 적용됩니다.
//
// 그때까지 `NEGA_GPU_MORPHOLOGY=1` 로만 켭니다. 커널·시험·이음매는 그대로 두어
// 오케스트레이터가 서면 바로 쓸 수 있습니다.
[[nodiscard]] bool morphology_enabled_by_environment() noexcept {
    char value[8]{};
    std::size_t length = 0U;
    if (getenv_s(&length, value, sizeof(value), "NEGA_GPU_MORPHOLOGY") != 0 || length == 0U) {
        return false;
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
        // ☠️ 형태학은 실측이 더 느려 기본에서 뺍니다(위 주석의 표). 반전은 왕복이 1회라
        //    사정이 다르므로 그대로 둡니다 — 근사이므로 스코프 안에서만 돕니다.
        static imaging::KernelAccelerator effective = kernel_table;
        if (!morphology_enabled_by_environment()) {
            effective.opening = nullptr;
            effective.closing = nullptr;
            effective.bipolar_top_hat = nullptr;
        }
        imaging::install_kernel_accelerator(&effective);
    });
}

}  // namespace negaflow::pipeline
