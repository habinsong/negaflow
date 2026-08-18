#pragma once

// 이웃을 보는 원시연산입니다. macOS 는 이 자리를 Apple 내장 필터가 채웁니다 —
// `CIGaussianBlur` · `CIBoxBlur` · `CIMedianFilter` · `CIAreaAverage`.
// **Windows 에는 그 내장 필터가 없어 우리가 만들어야 합니다. 여기가 실제 작업량입니다.**
//
// | | macOS | Windows CPU | 셰이더 |
// |---|---|---|---|
// | 박스 블러 | `CIBoxBlur` (`FilmScanDenoise.swift:154`) | `imaging/film_scan_denoise_filters.cpp` `box_blur` | `shaders/box_blur.hlsl` |
// | 가우시안 | `CIGaussianBlur` (네 곳) | 〃 `gaussian_blur` · `imaging/texture_stage_gaussian.h` | `shaders/gaussian_blur.hlsl` |
//
// 가이드 필터 4커널(`gfProduct`·`gfCoeffA`·`gfCoeffB`·`gfApply`)과 `filmScanShrink` 가
// 박스 평균에 물려 있습니다. 그래서 그 커널들보다 이것이 먼저입니다.

#include <cstdint>
#include <vector>

#include "negaflow/gpu/gpu_pointwise.h"

struct ID3D11ComputeShader;
struct ID3D11Buffer;
struct ID3D11UnorderedAccessView;
struct ID3D11ShaderResourceView;

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

// 3×3 중앙값입니다. macOS `CIMedianFilter`(`FilmScanDenoise.swift:171`),
// Windows CPU `imaging/film_scan_denoise_filters.cpp:77` `median3`.
//
// ☠️ **여기에는 부동소수 산술이 없습니다.** 중앙값은 아홉 개 중 하나를 고르는 일이라
//    고르는 방법이 달라도 고른 값은 같습니다 — CPU 의 `nth_element` 와 셰이더의 정렬
//    네트워크는 **비트 단위로 같은 값**을 냅니다. 평균·보간을 넣으면 그 성질이 깨집니다.
//
// 알파는 원본을 그대로 씁니다. CPU 의 `Rgb` 가 알파를 들고 다니지 않습니다.
class GpuMedian3 final {
public:
    GpuMedian3() noexcept = default;
    ~GpuMedian3();

    GpuMedian3(const GpuMedian3&) = delete;
    GpuMedian3& operator=(const GpuMedian3&) = delete;
    GpuMedian3(GpuMedian3&& other) noexcept;
    GpuMedian3& operator=(GpuMedian3&& other) noexcept;

    [[nodiscard]] static GpuKernelStatus create(const GpuDevice& device, GpuMedian3& kernel) noexcept;

    // 한 패스입니다. `source` 와 `destination` 은 서로 달라야 합니다.
    // `med5`(중앙값 두 번)는 호출부가 이것을 두 번 걸어 만듭니다 — CPU `film_scan_denoise_tile.cpp:83`
    // 이 그렇게 합니다.
    [[nodiscard]] GpuKernelStatus dispatch(
        const GpuDevice& device,
        const GpuWorkingImage& source,
        GpuWorkingImage& destination) const noexcept;

    [[nodiscard]] bool is_valid() const noexcept { return kernel_.is_valid(); }

private:
    GpuPointwiseKernel kernel_{};
};

// 가장자리 처리입니다. CPU `texture_stage_math.h:29` `GaussianEdgeMode` 와 같은 순서입니다 —
// 셰이더가 이 정수를 그대로 받으므로 순서를 바꾸지 마십시오.
enum class GpuGaussianEdgeMode : std::int32_t {
    // 경계 화소를 늘립니다. `film_scan_denoise` 의 가우시안이 이것입니다.
    clamp = 0,
    // 경계 화소 자신을 접습니다(`-1 → 0`, `limit → limit - 1`). Core Image 의 동작입니다.
    mirror = 1,
    // 범위 밖은 **더하지 않습니다.** 가중치 합이 줄어 가장자리가 어두워집니다.
    transparent = 2,
};

// 분리형(수평 → 수직) 가우시안입니다.
//
// ☠️ 가중치는 **호스트가 CPU 와 같은 코드로** 계산합니다(`weights_for_sigma`). 셰이더에서
//    `exp` 를 부르면 CPU 와 마지막 비트가 갈리고 그 차이가 전 화소에 곱해집니다.
class GpuGaussianBlur final {
public:
    GpuGaussianBlur() noexcept = default;
    ~GpuGaussianBlur();

    GpuGaussianBlur(const GpuGaussianBlur&) = delete;
    GpuGaussianBlur& operator=(const GpuGaussianBlur&) = delete;
    GpuGaussianBlur(GpuGaussianBlur&& other) noexcept;
    GpuGaussianBlur& operator=(GpuGaussianBlur&& other) noexcept;

    [[nodiscard]] static GpuKernelStatus create(
        const GpuDevice& device,
        GpuGaussianBlur& kernel) noexcept;

    // `imaging/coreimage_gaussian.h` 의 `coreimage_gaussian_effective_sigma` 로 σ 를 구하고
    // `-support…+support` 의 정규화 가중치를 만듭니다. CPU 두 판과 **같은 계산**입니다:
    // `film_scan_denoise_filters.cpp:19-31` · `texture_stage_gaussian.h:31-42`.
    //
    // ⚠️ 지원 반경 하한이 CPU 두 판에서 다릅니다 — `texture_stage` 는 `max(1, …)` 로 1 을
    //    보장하고 `film_scan_denoise` 는 그러지 않습니다. `minimum_support` 로 부르는 쪽이
    //    자기 판을 고릅니다. **여기서 한쪽으로 통일하지 마십시오.**
    [[nodiscard]] static std::vector<float> weights_for_sigma(float sigma, int minimum_support);

    // ☠️ **CPU 에 가우시안 가중치를 만드는 식이 두 가지 있습니다. 합치지 마십시오.**
    //    `imaging/digital_halation.cpp:51` `gaussian_weights` 는 위와 다릅니다:
    //      · Core Image 분산 보정 **0.08 이 없습니다** — 지수도 반경도 생 σ 를 씁니다.
    //      · 지수와 합계를 **`double` 로** 굴리고 마지막에 float 로 내립니다.
    //      · 지원 반경은 `max(1, ceil(3σ))`.
    //    같은 "가우시안" 이라도 값이 다르므로 **부르는 쪽이 자기 것을 고릅니다.**
    [[nodiscard]] static std::vector<float> weights_for_halation_sigma(float sigma);

    // `source` → `scratch`(수평) → `destination`(수직). 세 장이 모두 같은 크기여야 하고
    // 서로 달라야 합니다.
    //
    // `weights` 는 `weights_for_sigma` 가 준 것이어야 하고 길이는 홀수여야 합니다
    // (`radius * 2 + 1`). 길이 1 이면 흐림이 없어 원본을 그대로 내보냅니다.
    [[nodiscard]] GpuKernelStatus dispatch(
        const GpuDevice& device,
        const GpuWorkingImage& source,
        GpuWorkingImage& scratch,
        GpuWorkingImage& destination,
        const std::vector<float>& weights,
        GpuGaussianEdgeMode edge_mode,
        bool blur_alpha) const noexcept;

    [[nodiscard]] bool is_valid() const noexcept { return horizontal_ != nullptr; }

private:
    void reset() noexcept;
    // 가중치 버퍼는 탭 수가 바뀔 때만 다시 만듭니다. 같은 σ 로 프레임마다 부르는 경로에서
    // 매번 만들면 그 비용이 커널보다 큽니다.
    [[nodiscard]] GpuKernelStatus ensure_weights(
        const GpuDevice& device,
        const std::vector<float>& weights) const noexcept;

    ID3D11ComputeShader* horizontal_{nullptr};
    ID3D11ComputeShader* vertical_{nullptr};
    ID3D11Buffer* constants_{nullptr};
    mutable ID3D11Buffer* weights_{nullptr};
    mutable ID3D11ShaderResourceView* weights_view_{nullptr};
    mutable std::size_t weight_capacity_{0};
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

// 밉맵 한 단계 축소입니다. CPU 판은 `imaging/mipmap_downsampler.cpp` 의 `halve` 이고
// **비트 단위로 같습니다** — float32 덧셈 셋과 2의 거듭제곱 곱셈뿐이라 그렇습니다.
//
// 이 결과가 파라메트릭 톤 커브의 밴드 백분위로 가므로 근사면 출력 화소가 달라집니다.
// 최종 이중선형 보간은 CPU 판이 `double` 을 쓰므로 여기서 하지 않습니다 — 큰 축소만
// GPU 가 하고 작아진 뒤의 보간은 CPU 가 그대로 합니다.
class GpuMipHalve final {
public:
    GpuMipHalve() noexcept = default;
    ~GpuMipHalve();

    GpuMipHalve(const GpuMipHalve&) = delete;
    GpuMipHalve& operator=(const GpuMipHalve&) = delete;
    GpuMipHalve(GpuMipHalve&& other) noexcept;
    GpuMipHalve& operator=(GpuMipHalve&& other) noexcept;

    [[nodiscard]] static GpuKernelStatus create(
        const GpuDevice& device,
        GpuMipHalve& kernel) noexcept;

    // `destination` 은 각 변이 `max(1, source/2)` 여야 합니다.
    [[nodiscard]] GpuKernelStatus dispatch(
        const GpuDevice& device,
        const GpuWorkingImage& source,
        GpuWorkingImage& destination) const noexcept;

    // CPU 판이 고르는 단계 수와 같은 셈입니다 — `floor(log2(source_width / target_width))`.
    // 부모가 2보다 작아지면 거기서 멈추는 것도 같습니다.
    [[nodiscard]] static int wanted_level_count(
        std::uint32_t source_width,
        std::uint32_t target_width) noexcept;

    [[nodiscard]] bool is_valid() const noexcept { return shader_ != nullptr; }

private:
    void reset() noexcept;

    ID3D11ComputeShader* shader_{nullptr};
    ID3D11Buffer* constants_{nullptr};
};

// 전 화소 유한성 확인입니다. CPU 판은 `core/pixel.cpp` `validate_finite_pixels`.
//
// ☠️ **"있다/없다" 만 말합니다.** CPU 판은 어느 행이 처음 실패했는지까지 돌려주므로,
//    플래그가 서면 호출부가 CPU 판을 그대로 부릅니다. 실패는 드물고, 드문 쪽에 비용을
//    몰아주는 것이 맞습니다.
class GpuFiniteCheck final {
public:
    GpuFiniteCheck() noexcept = default;
    ~GpuFiniteCheck();

    GpuFiniteCheck(const GpuFiniteCheck&) = delete;
    GpuFiniteCheck& operator=(const GpuFiniteCheck&) = delete;
    GpuFiniteCheck(GpuFiniteCheck&& other) noexcept;
    GpuFiniteCheck& operator=(GpuFiniteCheck&& other) noexcept;

    [[nodiscard]] static GpuKernelStatus create(
        const GpuDevice& device,
        GpuFiniteCheck& kernel) noexcept;

    // `all_finite` 는 전 화소의 RGB 가 유한할 때만 참입니다. 알파는 보지 않습니다 —
    // CPU 판이 그렇습니다.
    [[nodiscard]] GpuKernelStatus dispatch(
        const GpuDevice& device,
        const GpuWorkingImage& source,
        bool& all_finite) const noexcept;

    [[nodiscard]] bool is_valid() const noexcept { return shader_ != nullptr; }

private:
    void reset() noexcept;

    ID3D11ComputeShader* shader_{nullptr};
    ID3D11Buffer* constants_{nullptr};
    ID3D11Buffer* flag_{nullptr};
    ID3D11UnorderedAccessView* flag_view_{nullptr};
    ID3D11Buffer* readback_{nullptr};
};

}  // namespace negaflow::gpu
