#pragma once

// GPU 로 `apply_film_scan_denoise` 한 장을 처리하는 사슬입니다.
//
// ☠️ **CPU 와 같은 타일로 돌아야 값이 같습니다. 전체를 한 번에 돌면 어긋납니다.**
//
//    박스 블러는 러닝 섬이라 **수학적으로는 창 안만 보지만 수치적으로는 그 행의 0번
//    화소부터 누적한 반올림을 들고 옵니다.** CPU 는 512px 타일마다 그 행의 0에서 새로
//    시작하고, 전체를 한 번에 도는 GPU 는 이미지의 0에서 시작합니다 — 같은 화소에서
//    누적 이력이 달라집니다. 그 차이는 가이드 필터의 `1 / (variance + 0.001)` 을 지나며
//    커집니다.
//
//    실측(600×130, 타일 경계 512 를 지나감, CPU 리프트를 올려 `pow` 를 제거한 상태):
//      전체 한 번에  → 최대 4.3e-05, 최악 화소가 전부 x > 512 (경계 너머)
//      CPU 와 같은 타일 → 아래 시험이 보고하는 값
//
//    에이프런 18 은 **필터 지원**으로는 충분합니다(가우시안 4 + 가이드 7 + 7). 모자란 것은
//    지원이 아니라 **누적 이력**입니다. 그래서 GPU 도 타일을 나눠야 하고, 이것은 성능
//    선택이 아니라 **값을 맞추기 위한 필수 조건**입니다.

#include <cstdint>
#include <vector>

#include "negaflow/core/pixel.h"
#include "negaflow/imaging/film_scan_denoise.h"

namespace negaflow::gpu {
class GpuDevice;
}

namespace gpu_film_scan_tests {

using negaflow::core::Rgba32F;

// 감마 리프트를 어디서 계산했는지. 두 가지를 다 돌려야 무엇이 틀렸는지 가릴 수 있습니다.
enum class LiftSource {
    // GPU `pow` — 실제 파이프라인이 쓸 경로.
    gpu,
    // CPU `std::pow` 결과를 올림 — **나머지 커널만** 재는 경로.
    cpu,
};

// `apply_film_scan_denoise` 와 같은 타일 나누기로 한 장을 처리합니다.
// 실패하면 빈 결과를 돌려주고 `failures` 를 올립니다.
[[nodiscard]] std::vector<Rgba32F> run_chain(
    const negaflow::gpu::GpuDevice& device,
    const std::vector<Rgba32F>& source,
    std::uint32_t width,
    std::uint32_t height,
    const negaflow::imaging::FilmScanDenoiseParameters& parameters,
    LiftSource lift_source);

// 타일 나누기 없이 전체를 한 번에 돕니다. 위 주석의 "어긋난다" 를 실제로 재기 위한 것이고,
// **제품 경로가 아닙니다.**
[[nodiscard]] std::vector<Rgba32F> run_chain_whole_image(
    const negaflow::gpu::GpuDevice& device,
    const std::vector<Rgba32F>& source,
    std::uint32_t width,
    std::uint32_t height,
    const negaflow::imaging::FilmScanDenoiseParameters& parameters,
    LiftSource lift_source);

extern int failures;
void expect(bool condition, const char* message);

}  // namespace gpu_film_scan_tests
