#pragma once

// macOS `filmScanShrink`(`ChromabaseMetalKernels.swift:362`) 와
// Windows CPU `imaging/film_scan_denoise_tile.cpp` `process_tile` 의 화소 루프입니다.
//
// 이웃을 보는 여섯 입력은 **이미 만들어져 있어야 합니다.** 만드는 도구는
// `gpu_neighborhood.h` 에 있습니다 — 가우시안(fine) · 가이드 필터(middle·coarse) ·
// 3×3 중앙값(med3·med5). 그 순서와 반경은 `film_scan_denoise_tile.cpp:72-83` 입니다.
//
// ☠️ **전체 이미지를 한 번에 도는 오케스트레이터는 아직 없습니다.** CPU 는 512px 타일에
//    18px 에이프런으로 도는데, 그 에이프런이 필터 지원(가우시안 4 + 가이드 7 + 7)과
//    **정확히 같아서** 타일 결과와 전체 이미지 결과가 같습니다
//    (`film_scan_denoise.h:17-19` 의 주석이 그 계산입니다).
//    그러나 GPU 에서 전체를 한 번에 돌면 중간 텍스처가 13장 필요하고, 24MP float32 RGBA
//    에서는 **5 GB** 입니다. 타일이 GPU 에서도 필요합니다 —
//    [`04-gpu-plan.md`](../../../../docs/audit/04-gpu-plan.md) 8절의 위험 표와 같은 자리입니다.
//    **재기 전에는 타일 크기를 정하지 마십시오.**

#include <cstdint>

#include "negaflow/gpu/gpu_pointwise.h"
#include "negaflow/imaging/film_scan_denoise.h"

namespace negaflow::gpu {

class GpuDevice;
class GpuWorkingImage;

// `extract_lifted_tile`(`film_scan_denoise_tile.cpp:13`) 입니다 — `pow(clamp01(rgb), power)`.
// 되돌리는 것은 `GpuFilmScanShrink` 의 마지막 줄입니다.
class GpuGammaLift final {
public:
    GpuGammaLift() noexcept = default;

    [[nodiscard]] static GpuKernelStatus create(const GpuDevice& device, GpuGammaLift& kernel) noexcept;

    [[nodiscard]] GpuKernelStatus dispatch(
        const GpuDevice& device,
        const GpuWorkingImage& source,
        GpuWorkingImage& destination,
        float power) const noexcept;

    [[nodiscard]] bool is_valid() const noexcept { return kernel_.is_valid(); }

private:
    GpuPointwiseKernel kernel_{};
};

class GpuFilmScanShrink final {
public:
    // 이미지마다 한 번 정해지는 값들입니다. `process_tile:85-101` 이 화소 루프 **밖에서**
    // 계산하는 것과 같은 목록이고, `resolve` 가 같은 식으로 만듭니다.
    struct Parameters final {
        float base_luma_threshold{0.0F};
        float base_chroma_threshold{0.0F};
        float impulse_luma_threshold{0.0F};
        float impulse_chroma_threshold{0.0F};
        float shadow_boost{0.0F};
        float dark_tone_scale{0.0F};
        float highlight_chroma{0.0F};
        float highlight_luma_protect{0.0F};
        float detail_scale{0.0F};
        float grain_protect{0.0F};
        float inverse_gamma_lift_power{imaging::film_scan_denoise_inverse_gamma_lift_power};
        bool monochrome{false};
    };

    // `process_tile:85-101` 과 `film_scan_denoise_film_scalars` 를 그대로 씁니다.
    // 필름별 표는 공개 헤더에 한 벌만 있습니다 — 여기서 숫자를 다시 적지 마십시오.
    [[nodiscard]] static Parameters resolve(
        const imaging::FilmScanDenoiseParameters& parameters) noexcept;

    GpuFilmScanShrink() noexcept = default;
    ~GpuFilmScanShrink();

    GpuFilmScanShrink(const GpuFilmScanShrink&) = delete;
    GpuFilmScanShrink& operator=(const GpuFilmScanShrink&) = delete;
    GpuFilmScanShrink(GpuFilmScanShrink&& other) noexcept;
    GpuFilmScanShrink& operator=(GpuFilmScanShrink&& other) noexcept;

    [[nodiscard]] static GpuKernelStatus create(
        const GpuDevice& device,
        GpuFilmScanShrink& kernel) noexcept;

    // 여섯 입력이 전부 같은 크기여야 하고 `destination` 과 달라야 합니다.
    // 전부 **감마 리프트된 도메인**이어야 합니다 — 되돌리기는 이 커널이 합니다.
    [[nodiscard]] GpuKernelStatus dispatch(
        const GpuDevice& device,
        const GpuWorkingImage& source,
        const GpuWorkingImage& median_three,
        const GpuWorkingImage& median_five,
        const GpuWorkingImage& fine,
        const GpuWorkingImage& middle,
        const GpuWorkingImage& coarse,
        GpuWorkingImage& destination,
        const Parameters& parameters) const noexcept;

    [[nodiscard]] bool is_valid() const noexcept { return shader_ != nullptr; }

private:
    void reset() noexcept;

    ID3D11ComputeShader* shader_{nullptr};
    ID3D11Buffer* constants_{nullptr};
};

}  // namespace negaflow::gpu
