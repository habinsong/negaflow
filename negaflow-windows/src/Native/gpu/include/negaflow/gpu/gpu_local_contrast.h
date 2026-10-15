#pragma once

// 부분 대비를 GPU 에서 겁니다. macOS `DetailEnhancement.localContrast`(Metal 커널), Windows CPU
// `imaging/detail_enhancement.cpp` `apply_local_contrast` 에 대응합니다.
//
// 왜 필요한가 — SP 타겟은 사용자 부분 대비와 별개로 기본 부분 대비(`sp_target_local_contrast`)를
// 얹습니다. 그것이 CPU 질감 단계에만 있으면 마무리 단계에서 상주 사슬이 끊겨, SP 프리뷰마다
// 화상을 통째로 내리고 발행도 CPU 로 떨어집니다. 이 커널이 상주 화상 위에서 그 자리를 맡습니다.
//
// 계수는 축소 해상도에서 구합니다(He & Sun 2015 고속 가이디드 필터). 축소 평면의 가우시안은
// `GpuGaussianBlur` 를 CPU 와 같은 가중치로 써서 값이 같고, 감마 변환의 `pow`·`tanh` 구현
// 차이만큼 CPU 와 갈립니다.

#include <cstdint>

#include "negaflow/gpu/gpu_pointwise.h"
#include "negaflow/gpu/gpu_working_image.h"

struct ID3D11ComputeShader;
struct ID3D11Buffer;

namespace negaflow::gpu {

class GpuDevice;
class GpuGaussianBlur;

class GpuLocalContrast final {
public:
    GpuLocalContrast() noexcept = default;
    ~GpuLocalContrast();

    GpuLocalContrast(const GpuLocalContrast&) = delete;
    GpuLocalContrast& operator=(const GpuLocalContrast&) = delete;

    [[nodiscard]] static GpuKernelStatus create(
        const GpuDevice& device,
        GpuLocalContrast& kernel) noexcept;

    // `source` → `destination`. 두 장은 같은 크기여야 하고 서로 달라야 합니다. `clarity` 는
    // −1…1 이며 계획(축소 배율·창·세기)은 CPU 와 같은 `imaging::plan_local_contrast` 가 정합니다.
    // 축소 평면 세 장은 이 객체가 들고, 크기가 바뀔 때만 다시 만듭니다.
    [[nodiscard]] GpuKernelStatus dispatch(
        const GpuDevice& device,
        const GpuGaussianBlur& blur,
        const GpuWorkingImage& source,
        GpuWorkingImage& destination,
        float clarity) noexcept;

    // 축소 평면을 놓습니다. 다음 `dispatch` 가 다시 만듭니다.
    void release_scratch() noexcept;

    [[nodiscard]] bool is_valid() const noexcept { return guide_ != nullptr; }

private:
    void reset() noexcept;
    [[nodiscard]] bool ensure_low(
        const GpuDevice& device,
        std::uint32_t width,
        std::uint32_t height) noexcept;

    ID3D11ComputeShader* guide_{nullptr};
    ID3D11ComputeShader* coefficients_{nullptr};
    ID3D11ComputeShader* apply_{nullptr};
    ID3D11Buffer* constants_{nullptr};
    GpuWorkingImage low_[3]{};
};

} // namespace negaflow::gpu
