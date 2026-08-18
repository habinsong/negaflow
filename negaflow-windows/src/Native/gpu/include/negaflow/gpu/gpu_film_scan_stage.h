#pragma once

// `imaging::apply_film_scan_denoise` 를 GPU 에서 통째로 돌립니다.
// CPU 판의 주석 원문 — *"On a 17 MP scan this stage was by far the most expensive in the
// whole develop."*
//
// ☠️ **CPU 와 같은 512/18 타일로 나눕니다. 전체를 한 번에 돌면 값이 갈립니다.**
//    박스 블러가 러닝 섬이라 창 밖을 안 봐도 **그 행 0번부터의 누적 반올림**이 따라옵니다.
//    실측(600×130): 전체 한 번에 4.3e-05, CPU 와 같은 타일 1.2e-07.
//    자세한 것은 `04-gpu-plan.md` 0.5절 · `13-performance-playbook.md` 15절.
//
//    부수 효과로 메모리도 풀립니다 — 중간 텍스처가 15장이라 24MP 를 통째로 올리면 5 GB
//    인데, 548×548 타일이면 72 MB 입니다.
//
// ⚠️ 감마 리프트의 `pow` 때문에 CPU 와 **2e-05 ~ 6e-05** 벌어집니다. HLSL `pow` 는
//    `exp2(y*log2(x))` 이고 D3D11 이 그 둘에 상대오차 2^-21 을 허용하므로 `std::pow` 와
//    마지막 비트를 맞출 방법이 표준 안에 없습니다. 그 1~2 ulp 를 사슬 안의
//    `1/(variance+0.001)` 이 수백 배로 키웁니다 — `04-gpu-plan.md` 0.6절.
//    **그래서 이 경로는 골든(바이트 일치)이 걸린 곳에 쓰면 안 됩니다.**

#include <cstdint>

#include "negaflow/gpu/gpu_pointwise.h"
#include "negaflow/imaging/film_scan_denoise.h"

namespace negaflow::gpu {

class GpuDevice;

struct GpuFilmScanDenoiseResult final {
    // 참이면 GPU 가 실제로 처리했습니다. 거짓이면 이미지는 손대지 않았고 CPU 로 가야 합니다.
    bool handled{false};
    imaging::FilmScanDenoiseStatus status{imaging::FilmScanDenoiseStatus::ok};
    imaging::FilmScanDenoiseInfo info{};
};

class GpuFilmScanDenoiseStage final {
public:
    GpuFilmScanDenoiseStage() noexcept = default;
    ~GpuFilmScanDenoiseStage();

    GpuFilmScanDenoiseStage(const GpuFilmScanDenoiseStage&) = delete;
    GpuFilmScanDenoiseStage& operator=(const GpuFilmScanDenoiseStage&) = delete;

    [[nodiscard]] static GpuKernelStatus create(
        const GpuDevice& device,
        GpuFilmScanDenoiseStage& stage) noexcept;

    // `image` 를 제자리에서 바꿉니다. `handled` 가 거짓이면 손대지 않았습니다.
    [[nodiscard]] GpuFilmScanDenoiseResult apply(
        const GpuDevice& device,
        imaging::WorkingImage& image,
        const imaging::FilmScanDenoiseParameters& parameters) const noexcept;

    [[nodiscard]] bool is_valid() const noexcept { return state_ != nullptr; }

private:
    struct State;
    State* state_{nullptr};
};

}  // namespace negaflow::gpu
