// 디지털 필름 룩 **사슬 전체**의 CPU/GPU 동치 시험.
//
// 커널 하나하나는 각자 동치 시험이 있습니다. 이 시험이 보는 것은 **사슬**입니다 —
// 순서·게이트·적용 플래그가 CPU 와 같은지.
//
// ☠️ 이 시험이 없으면 오케스트레이터가 커널을 하나 빠뜨리거나 순서를 바꿔도 아무도
//    모릅니다. 커널 동치 시험은 전부 통과한 채로 결과만 틀립니다.
//
// 겨루는 법: 같은 입력에 대해
//   ① `NEGA_GPU=0` 과 같은 상태(가속 표를 안 걸고) CPU 사슬을 돌린 결과
//   ② 가속 표를 걸고 `ApproximateAcceleratorScope` 안에서 돌린 결과
// 를 비교합니다. ②가 실제로 GPU 를 탔는지는 적용 플래그와 오차가 0 이 아니라는 것으로는
// 알 수 없으므로, **가속기 가용성**을 먼저 확인하고 안 되면 건너뜁니다.

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <memory>
#include <utility>
#include <vector>

#include "negaflow/imaging/film_emulation_acutance.h"
#include "negaflow/imaging/film_emulation_color.h"
#include "negaflow/imaging/kernel_accelerator.h"
#include "negaflow/imaging/working_film_look.h"
#include "negaflow/pipeline/gpu_accelerator.h"

namespace {

using negaflow::core::Rgba32F;
using negaflow::imaging::FilmEmulation;
using negaflow::imaging::FilmEmulationColorCube;
using negaflow::imaging::WorkingFilmLookParameters;
using negaflow::imaging::WorkingFilmLookResult;
using negaflow::imaging::WorkingFilmLookWorkspace;
using negaflow::imaging::WorkingImage;
using negaflow::pipeline::GpuAccelerator;

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

// 사슬에는 sRGB 왕복의 `pow` 가 여러 번 들어가고 그 앞뒤로 곱셈이 쌓입니다.
// 커널 하나의 상한(1e-5)을 사슬 전체에 그대로 요구하지 않고, 실측으로 정한 값을 씁니다.
constexpr float tolerance = 1.0e-5F;
constexpr std::uint32_t width = 320U;
constexpr std::uint32_t height = 240U;

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
            const float level = 0.01F + (0.95F * static_cast<float>(x) /
                                         static_cast<float>(width));
            const bool spot = ((x / 29U) + (y / 17U)) % 4U == 0U;
            image.pixels[(static_cast<std::size_t>(y) * width) + x] = Rgba32F{
                spot ? 0.97F : level,
                std::clamp(level * 0.78F + (noise * 0.04F), 0.0F, 1.0F),
                std::clamp(level * 0.55F, 0.0F, 1.0F),
                0.3F + (0.5F * noise)};
        }
    }
    return image;
}

struct Workspace final {
    std::unique_ptr<FilmEmulationColorCube> cube{
        std::make_unique<FilmEmulationColorCube>()};
    std::vector<negaflow::imaging::FilmEmulationAcutanceScratchPixel> acutance{
        negaflow::imaging::film_emulation_acutance_scratch_pixel_count(width)};

    [[nodiscard]] WorkingFilmLookWorkspace view() noexcept {
        return {cube.get(), {acutance.data(), acutance.size()}};
    }
};

void chain_matches_cpu(
    const char* const label,
    const FilmEmulation emulation,
    const double intensity,
    const double grain_override,
    const double halation_override) {
    const WorkingFilmLookParameters parameters{
        negaflow::imaging::DevelopSourceKind::rendered_digital,
        emulation,
        intensity,
        grain_override,
        halation_override,
        false};

    Workspace cpu_workspace{};
    const WorkingFilmLookResult cpu = negaflow::imaging::apply_working_film_look(
        make_image(), parameters, cpu_workspace.view());
    expect(
        cpu.status == negaflow::imaging::WorkingFilmLookStatus::ok,
        "CPU film look must succeed");
    if (cpu.image.pixels.empty()) {
        return;
    }

    Workspace gpu_workspace{};
    WorkingFilmLookResult gpu{};
    {
        // 근사 가속은 이 스코프 안에서만 돕니다 — 파이프라인의 프리뷰·검출 경로와 같습니다.
        const negaflow::imaging::ApproximateAcceleratorScope scope{};
        gpu = negaflow::imaging::apply_working_film_look(
            make_image(), parameters, gpu_workspace.view());
    }
    expect(
        gpu.status == negaflow::imaging::WorkingFilmLookStatus::ok,
        "GPU film look must succeed");
    if (gpu.image.pixels.empty()) {
        return;
    }

    // 적용 플래그가 다르면 게이트를 하나 빠뜨린 것입니다. 값보다 먼저 봅니다.
    expect(
        cpu.info.digital_halation_applied == gpu.info.digital_halation_applied,
        "halation applied flag must match");
    expect(cpu.info.color_applied == gpu.info.color_applied, "color flag must match");
    expect(
        cpu.info.acutance_applied == gpu.info.acutance_applied,
        "acutance flag must match");
    expect(
        cpu.info.digital_color_preset_applied == gpu.info.digital_color_preset_applied,
        "preset flag must match");
    expect(
        cpu.info.digital_grain_applied == gpu.info.digital_grain_applied,
        "grain flag must match");

    float worst = 0.0F;
    for (std::size_t index = 0U; index < cpu.image.pixels.size(); ++index) {
        const Rgba32F& left = cpu.image.pixels[index];
        const Rgba32F& right = gpu.image.pixels[index];
        worst = std::max(worst, std::abs(left.red - right.red));
        worst = std::max(worst, std::abs(left.green - right.green));
        worst = std::max(worst, std::abs(left.blue - right.blue));
        worst = std::max(worst, std::abs(left.alpha - right.alpha));
    }
    if (worst > tolerance) {
        std::cerr << "FAIL: " << label << " film look chain delta " << worst
                  << " exceeds " << tolerance << '\n';
        ++failures;
    } else {
        std::cout << label << " film look chain max delta " << worst << '\n';
    }
}

}  // namespace

int main() {
    negaflow::pipeline::install_gpu_kernel_accelerator();
    if (!GpuAccelerator::shared().available()) {
        std::cout << "GPU unavailable — film look chain test skipped\n";
        return 0;
    }
    std::cout << "adapter: " << GpuAccelerator::shared().adapter_description() << '\n';

    chain_matches_cpu("portra_400", FilmEmulation::portra_400, 0.8, 0.0, 0.0);
    chain_matches_cpu("velvia_50", FilmEmulation::velvia_50, 1.0, 0.0, 0.0);
    // 오버라이드 두 개를 따로 밀어 헐레이션·그레인의 세기 경로를 가릅니다.
    chain_matches_cpu("vision3_500t", FilmEmulation::vision3_500t, 0.5, 0.9, 0.2);
    // 세기가 아주 작으면 사슬이 거의 전부 건너뛰어야 합니다.
    chain_matches_cpu("portra_400 low", FilmEmulation::portra_400, 0.002, 0.0, 0.0);

    if (failures != 0) {
        std::cerr << failures << " failure(s)\n";
        return 1;
    }
    std::cout << "gpu film look stage tests passed\n";
    return 0;
}
