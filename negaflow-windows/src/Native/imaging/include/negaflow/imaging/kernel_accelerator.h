#pragma once

// `imaging` 안에서 GPU 커널을 부를 수 있게 하는 이음매입니다.
//
// 왜 함수 표인가 — 의존 방향이 `gpu → imaging` 이라 `imaging` 이 `gpu` 를 링크할 수
// 없습니다. 링크하면 순환입니다. 그래서 `imaging` 은 **표만 알고**, 그 표를
// `pipeline`(둘 다 링크하는 층)이 채웁니다.
//
// ☠️ **표에 넣어도 되는 것과 아닌 것이 다릅니다.**
//
//  · **정확한 것** — 값이 CPU 와 **비트 단위로 같음이 증명되는** 커널.
//    형태학(min/max)이 그렇습니다: 창 안에서 **하나를 고르는** 일이라 부동소수 산술이
//    없고, 창과 가장자리 처리가 같으면 고른 값이 같습니다. 이런 것은 **언제나** 켭니다 —
//    내보내기·골든에서도 값이 안 바뀝니다.
//
//  · **근사한 것** — 곱셈·덧셈이 들어가 CPU 와 마지막 비트가 다를 수 있는 커널.
//    `ApproximateAcceleratorScope` 안에서만 돕니다. 프리뷰·검출만 그 스코프를 엽니다.
//    **내보내기·골든 경로는 절대 열지 마십시오.**

#include <cstdint>

namespace negaflow::imaging {

// 어느 형태학인지. 표의 함수 셋을 한 구현으로 모을 때 씁니다.
enum class MorphologyKind : std::uint8_t {
    // 침식 → 팽창. 밝은 티끌을 지웁니다.
    opening = 0,
    // 팽창 → 침식. 어두운 티끌을 지웁니다.
    closing,
    // `max(max(0, source − opened), max(0, closed − source))`.
    // ☠️ 반경이 0 이면 CPU 는 **원본이 아니라 전부 0** 을 냅니다. 가속도 같아야 합니다.
    bipolar_top_hat,
};

// 단일 채널 평면 형태학입니다. CPU 판(`grain_mend_morphology.cpp`)과 같은 셈이어야 합니다.
// `source` 와 `destination` 은 `width * height` 개이고 겹치지 않아야 합니다.
// 처리했으면 `true`. `false` 면 호출부가 CPU 로 갑니다.
using MorphologyPlaneFunction = bool (*)(
    const float* source,
    float* destination,
    std::uint32_t width,
    std::uint32_t height,
    std::uint32_t radius) noexcept;

// 산란·헐레이션입니다. `pixels` 는 `stride_pixels * height` 개의 RGBA float 이고
// 제자리에서 바뀝니다. 재료·세기는 CPU 판과 같은 값이어야 합니다.
using DigitalHalationFunction = bool (*)(
    float* pixels,
    std::uint32_t width,
    std::uint32_t height,
    std::uint32_t stride_pixels,
    const double* scatter_strength,
    const double* halation_strength,
    double radius_ratio,
    double strength) noexcept;

struct KernelAccelerator final {
    // ── 정확한 것 (언제나 켭니다) ────────────────────────────────────────────
    MorphologyPlaneFunction opening{nullptr};
    MorphologyPlaneFunction closing{nullptr};
    MorphologyPlaneFunction bipolar_top_hat{nullptr};

    // ── 근사한 것 (`ApproximateAcceleratorScope` 안에서만) ────────────────────
    DigitalHalationFunction digital_halation{nullptr};
};

// 프로세스 시작에 한 번 설치합니다. `nullptr` 을 주면 해제합니다.
// 표는 호출부가 소유하고 프로세스 수명 동안 살아 있어야 합니다.
void install_kernel_accelerator(const KernelAccelerator* table) noexcept;

[[nodiscard]] const KernelAccelerator* kernel_accelerator() noexcept;

// 이 스코프 안에서만 **근사** 가속이 돕니다. 스레드마다 따로입니다.
// 내보내기·골든 경로는 열지 않으므로 값이 그대로입니다.
class ApproximateAcceleratorScope final {
public:
    ApproximateAcceleratorScope() noexcept;
    ~ApproximateAcceleratorScope();

    ApproximateAcceleratorScope(const ApproximateAcceleratorScope&) = delete;
    ApproximateAcceleratorScope& operator=(const ApproximateAcceleratorScope&) = delete;
};

// 지금 이 스레드에서 근사 가속이 허용되는지.
[[nodiscard]] bool approximate_acceleration_allowed() noexcept;

}  // namespace negaflow::imaging
