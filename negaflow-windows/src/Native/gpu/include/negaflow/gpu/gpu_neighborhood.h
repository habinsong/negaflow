#pragma once

// 이웃을 보는 원시연산입니다. macOS 는 이 자리를 Apple 내장 필터가 채웁니다 —
// `CIGaussianBlur` · `CIBoxBlur` · `CIMedianFilter` · `CIAreaAverage`.
// **Windows 에는 그 내장 필터가 없어 우리가 만들어야 합니다. 여기가 실제 작업량입니다.**
//
// | | macOS | Windows CPU | 셰이더 |
// |---|---|---|---|
// | 박스 블러 | `CIBoxBlur` (`FilmScanDenoise.swift:154`) | `imaging/film_scan_denoise_filters.cpp` `box_blur` | `shaders/box_blur.hlsl` |
//
// 가이드 필터 4커널(`gfProduct`·`gfCoeffA`·`gfCoeffB`·`gfApply`)과 `filmScanShrink` 가
// 박스 평균에 물려 있습니다. 그래서 그 커널들보다 이것이 먼저입니다.

#include <cstdint>

#include "negaflow/gpu/gpu_pointwise.h"

struct ID3D11ComputeShader;
struct ID3D11Buffer;

namespace negaflow::gpu {

class GpuDevice;
class GpuWorkingImage;

// 분리형(수평 → 수직) 박스 블러입니다.
//
// ☠️ CPU 판은 러닝 섬이라 부동소수 누적 **순서**가 결과에 남습니다. 이 구현은 행/열마다
//    스레드 하나를 두어 같은 순서로 누적합니다. 순진한 "반경만큼 다시 더하기" 로 바꾸면
//    화소당 O(r) 로 느려질 뿐 아니라 값도 갈립니다.
class GpuBoxBlur final {
public:
    GpuBoxBlur() noexcept = default;
    ~GpuBoxBlur();

    GpuBoxBlur(const GpuBoxBlur&) = delete;
    GpuBoxBlur& operator=(const GpuBoxBlur&) = delete;
    GpuBoxBlur(GpuBoxBlur&& other) noexcept;
    GpuBoxBlur& operator=(GpuBoxBlur&& other) noexcept;

    [[nodiscard]] static GpuKernelStatus create(const GpuDevice& device, GpuBoxBlur& kernel) noexcept;

    // `source` → `scratch`(수평) → `destination`(수직). 세 장이 모두 같은 크기여야 하고
    // 서로 달라야 합니다 — D3D11 은 한 자원을 SRV 와 UAV 로 동시에 묶을 수 없습니다.
    //
    // `radius` 가 0 이면 CPU 판과 같이 원본을 그대로 내보냅니다(창 크기 1).
    //
    // ☠️ **RGB 와 알파의 누적 순서가 다릅니다.** CPU 의 `box_blur` 가 두 벌이고 괄호가
    //    다르기 때문입니다 — `std::vector<Rgb>` 판은 `(sum + a) - b`,
    //    `std::vector<float>` 판은 `sum + (a - b)`. 이 커널은 **RGB 에 Rgb 판, 알파에
    //    float 판**을 적용합니다. `box_blur` 를 부르는 곳은 `guided_base` 뿐이고
    //    (`film_scan_denoise_tile.cpp:79,81`), 거기서 RGB 자리에 오는 것은 항상 `Rgb`,
    //    알파 자리에 오는 것은 항상 스칼라(guide·guide²)입니다.
    //    **알파에 Rgb 의미의 스칼라를 담아 넘기지 마십시오 — 순서가 어긋납니다.**
    [[nodiscard]] GpuKernelStatus dispatch(
        const GpuDevice& device,
        const GpuWorkingImage& source,
        GpuWorkingImage& scratch,
        GpuWorkingImage& destination,
        std::int32_t radius,
        // 참이면 알파까지 흐립니다. 가이드 필터가 네 스칼라를 한 텍스처에 담아
        // 한 번에 흐리려고 씁니다. 거짓이면 CPU 의 Rgb 경로와 같이 알파를 보존합니다.
        bool blur_alpha = false) const noexcept;

    [[nodiscard]] bool is_valid() const noexcept { return horizontal_ != nullptr; }

private:
    void reset() noexcept;

    ID3D11ComputeShader* horizontal_{nullptr};
    ID3D11ComputeShader* vertical_{nullptr};
    ID3D11Buffer* constants_{nullptr};
};

// 가이드 필터입니다. macOS `gfProduct`·`gfCoeffA`·`gfCoeffB`·`gfApply` 넷과
// Windows CPU `imaging/film_scan_denoise_filters.cpp` `guided_base` 에 대응합니다.
//
// 박스 평균이 O(1) 이므로 **창 크기와 무관한 O(1)** 입니다(원 논문 성질).
// 그래서 `GpuBoxBlur` 가 이것보다 먼저였습니다.
class GpuGuidedFilter final {
public:
    // 중간 텍스처를 몇 장 쓰는지. 호출부가 미리 잡아 두라고 공개합니다.
    static constexpr int scratch_count = 6;

    GpuGuidedFilter() noexcept = default;
    ~GpuGuidedFilter();

    GpuGuidedFilter(const GpuGuidedFilter&) = delete;
    GpuGuidedFilter& operator=(const GpuGuidedFilter&) = delete;
    GpuGuidedFilter(GpuGuidedFilter&& other) noexcept;
    GpuGuidedFilter& operator=(GpuGuidedFilter&& other) noexcept;

    [[nodiscard]] static GpuKernelStatus create(
        const GpuDevice& device,
        GpuGuidedFilter& kernel) noexcept;

    // `packed` 는 `(source.r, source.g, source.b, guide)` 로 채워 두어야 합니다.
    // `scratch` 는 `scratch_count` 장이어야 하고 전부 `packed` 와 같은 크기여야 합니다.
    // 결과는 `destination` 에 들어가고 알파는 `packed` 의 것을 그대로 씁니다.
    [[nodiscard]] GpuKernelStatus dispatch(
        const GpuDevice& device,
        const GpuBoxBlur& blur,
        const GpuWorkingImage& packed,
        GpuWorkingImage* scratch,
        GpuWorkingImage& destination,
        std::int32_t radius,
        float epsilon) const noexcept;

    [[nodiscard]] bool is_valid() const noexcept { return prepare_ != nullptr; }

private:
    void reset() noexcept;

    ID3D11ComputeShader* prepare_{nullptr};
    ID3D11ComputeShader* coefficients_{nullptr};
    ID3D11ComputeShader* apply_{nullptr};
    ID3D11Buffer* constants_{nullptr};
};

}  // namespace negaflow::gpu
