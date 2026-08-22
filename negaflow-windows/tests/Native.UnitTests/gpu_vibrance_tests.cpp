// CPU/GPU 동치 시험 — 실측 `CIVibrance` 표를 쓰는 커널 둘.
//
// **참조를 옮겨 적지 않습니다.** 진짜 CPU 함수 `apply_muted_scene_vibrance` ·
// `apply_color_model` 을 그대로 부르고 그 결과와 겨룹니다.
//
// **amount 판이 어긋나면 오차가 1e-5 가 아니라 0.0x 로 나옵니다.** 표는 amount 판
// 여섯 장이고 화소마다 두 장을 섞습니다. 판 선택을 GPU 가 따로 하면 어느 구간에서
// 한 장씩 밀리고, 그러면 색이 통째로 달라집니다. 그래서 amount 를 판 경계
// (−0.05·0.05·0.25·0.50·0.60·0.80) 안팎으로 여러 개 시험합니다.

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <vector>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_vibrance.h"
#include "negaflow/gpu/gpu_working_image.h"
#include "negaflow/imaging/color_model.h"
#include "negaflow/imaging/muted_scene_vibrance.h"

namespace {

using negaflow::core::Rgba32F;
using negaflow::gpu::GpuColorModel;
using negaflow::gpu::GpuDevice;
using negaflow::gpu::GpuDevicePreference;
using negaflow::gpu::GpuImageStatus;
using negaflow::gpu::GpuKernelStatus;
using negaflow::gpu::GpuMutedSceneVibrance;
using negaflow::gpu::GpuVibranceTable;
using negaflow::gpu::GpuWorkingImage;
using negaflow::imaging::ColorModelParameters;

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

constexpr float tolerance = 1.0e-5F;
constexpr std::uint32_t width = 288U;
constexpr std::uint32_t height = 192U;

// 33³ 격자 사이를 촘촘히 지나가게 만듭니다. 격자점만 밟으면 삼선형이 시험되지 않습니다.
[[nodiscard]] std::vector<Rgba32F> make_pattern() {
    std::vector<Rgba32F> pixels(static_cast<std::size_t>(width) * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const float u = static_cast<float>(x) / static_cast<float>(width - 1U);
            const float v = static_cast<float>(y) / static_cast<float>(height - 1U);
            pixels[(static_cast<std::size_t>(y) * width) + x] = Rgba32F{
                u,
                v,
                std::fabs(u - v),
                0.3F + (0.5F * u)};
        }
    }
    return pixels;
}

// 채도를 눌러 놓은 무늬. 장면 평균 채도가 0.24 아래여야 스테이지가 실제로 걸립니다.
// `saturation_scale` 을 바꾸면 스테이지가 정하는 세기가 달라져 **표의 다른 amount 판**을 탑니다.
[[nodiscard]] std::vector<Rgba32F> make_muted_pattern(const float saturation_scale) {
    std::vector<Rgba32F> pixels(static_cast<std::size_t>(width) * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const float u = static_cast<float>(x) / static_cast<float>(width - 1U);
            const float v = static_cast<float>(y) / static_cast<float>(height - 1U);
            const float grey = 0.05F + (0.9F * u);
            pixels[(static_cast<std::size_t>(y) * width) + x] = Rgba32F{
                std::clamp(grey + ((v - 0.5F) * saturation_scale), 0.0F, 1.0F),
                grey,
                std::clamp(grey - ((v - 0.5F) * saturation_scale), 0.0F, 1.0F),
                0.3F + (0.5F * u)};
        }
    }
    return pixels;
}

[[nodiscard]] float max_delta(
    const std::vector<Rgba32F>& left,
    const std::vector<Rgba32F>& right) {
    float worst = 0.0F;
    for (std::size_t index = 0U; index < left.size(); ++index) {
        worst = std::max(worst, std::abs(left[index].red - right[index].red));
        worst = std::max(worst, std::abs(left[index].green - right[index].green));
        worst = std::max(worst, std::abs(left[index].blue - right[index].blue));
        worst = std::max(worst, std::abs(left[index].alpha - right[index].alpha));
    }
    return worst;
}

// 흐린 장면 vibrance. **진짜 스테이지를 먼저 돌려** 그 스테이지가 정한 세기를 얻고,
// 같은 세기를 GPU 커널에 먹여 겨룹니다 — 세기를 시험이 지어내면 그 순간 시험이
// 제품과 다른 것을 재게 됩니다.
void muted_vibrance_matches_cpu(
    const GpuDevice& device,
    const GpuVibranceTable& table,
    const char* const label,
    const float saturation_scale) {
    const std::vector<Rgba32F> pixels = make_muted_pattern(saturation_scale);

    std::vector<Rgba32F> cpu = pixels;
    const negaflow::core::ImageView view{cpu.data(), cpu.size(), width, height, width};
    const negaflow::imaging::MutedSceneVibranceResult reference =
        negaflow::imaging::apply_muted_scene_vibrance(view, false);
    if (reference.status != negaflow::core::KernelStatus::ok) {
        expect(false, "CPU muted vibrance must succeed");
        return;
    }
    if (!reference.info.applied) {
        // 세기가 활성 문턱(0.01) 아래면 CPU 는 손대지 않습니다. 그 경우는 겨룰 것이 없습니다.
        std::cout << label << " muted vibrance identity (meanSat="
                  << reference.info.mean_saturation << ")\n";
        return;
    }
    const float amount = static_cast<float>(reference.info.amount);

    GpuMutedSceneVibrance kernel{};
    if (GpuMutedSceneVibrance::create(device, kernel) != GpuKernelStatus::ok) {
        expect(false, "muted vibrance kernel must be creatable");
        return;
    }
    GpuWorkingImage source{};
    GpuWorkingImage destination{};
    if (GpuWorkingImage::upload(device, pixels.data(), width, height, width, source) !=
            GpuImageStatus::ok ||
        GpuWorkingImage::create(device, width, height, destination) != GpuImageStatus::ok) {
        expect(false, "muted vibrance images must be creatable");
        return;
    }
    if (kernel.dispatch(device, table, source, destination, amount) != GpuKernelStatus::ok) {
        expect(false, "muted vibrance dispatch must succeed");
        return;
    }
    std::vector<Rgba32F> gpu(pixels.size());
    if (destination.download(device, gpu.data(), width) != GpuImageStatus::ok) {
        expect(false, "muted vibrance download must succeed");
        return;
    }

    const float worst = max_delta(cpu, gpu);
    if (worst > tolerance) {
        std::cerr << "FAIL: " << label << " muted vibrance delta " << worst << " exceeds "
                  << tolerance << '\n';
        ++failures;
    } else {
        std::cout << label << " muted vibrance(amount=" << amount << ") max delta " << worst
                  << '\n';
    }
}

void color_model_matches_cpu(
    const GpuDevice& device,
    const GpuVibranceTable& table,
    const char* const label,
    const ColorModelParameters& parameters,
    const char* const what) {
    const std::vector<Rgba32F> pixels = make_pattern();

    std::vector<Rgba32F> cpu = pixels;
    const negaflow::core::ConstImageView input{cpu.data(), cpu.size(), width, height, width};
    const negaflow::core::ImageView output{cpu.data(), cpu.size(), width, height, width};
    if (negaflow::imaging::apply_color_model(input, output, parameters) !=
        negaflow::core::KernelStatus::ok) {
        expect(false, "CPU color model must succeed");
        return;
    }

    GpuColorModel kernel{};
    if (GpuColorModel::create(device, kernel) != GpuKernelStatus::ok) {
        expect(false, "color model kernel must be creatable");
        return;
    }
    GpuWorkingImage source{};
    GpuWorkingImage destination{};
    if (GpuWorkingImage::upload(device, pixels.data(), width, height, width, source) !=
            GpuImageStatus::ok ||
        GpuWorkingImage::create(device, width, height, destination) != GpuImageStatus::ok) {
        expect(false, "color model images must be creatable");
        return;
    }
    if (kernel.dispatch(device, table, source, destination, parameters) !=
        GpuKernelStatus::ok) {
        expect(false, "color model dispatch must succeed");
        return;
    }
    std::vector<Rgba32F> gpu(pixels.size());
    if (destination.download(device, gpu.data(), width) != GpuImageStatus::ok) {
        expect(false, "color model download must succeed");
        return;
    }

    const float worst = max_delta(cpu, gpu);
    if (worst > tolerance) {
        std::cerr << "FAIL: " << label << ' ' << what << " delta " << worst << " exceeds "
                  << tolerance << '\n';
        ++failures;
    } else {
        std::cout << label << ' ' << what << " max delta " << worst << '\n';
    }
}

void run_all(const GpuDevice& device, const char* const label) {
    GpuVibranceTable table{};
    if (GpuVibranceTable::create(device, table) != GpuKernelStatus::ok) {
        expect(false, "vibrance table must be creatable");
        return;
    }

    // 채도를 여러 단계로 눌러 스테이지가 **서로 다른 amount 판**을 고르게 합니다 —
    // 판 선택이 어긋나면 여기서 크게 벌어집니다.
    for (const float scale : {0.02F, 0.06F, 0.12F, 0.20F, 0.35F}) {
        muted_vibrance_matches_cpu(device, table, label, scale);
    }

    ColorModelParameters full{};
    full.warmth = 0.35F;
    full.tint = -0.22F;
    full.color_depth = 0.4F;
    full.vibrance = 0.6F;
    full.saturation = -0.3F;
    full.red_primary = 0.12F;
    full.green_primary = -0.08F;
    full.blue_primary = 0.2F;
    color_model_matches_cpu(device, table, label, full, "color model (all)");

    ColorModelParameters vibrance_only{};
    vibrance_only.vibrance = -0.5F;
    color_model_matches_cpu(device, table, label, vibrance_only, "color model (negative vibrance)");

    // 임계 바로 아래 — 게이트가 닫혀야 합니다. 열리면 `1 + 0` 곱셈의 반올림이 붙습니다.
    ColorModelParameters below{};
    below.warmth = 0.0005F;
    below.saturation = 0.0009F;
    color_model_matches_cpu(device, table, label, below, "color model (below threshold)");
}

} // namespace

int main() {
    const GpuDevice warp = GpuDevice::create(GpuDevicePreference::warp_only);
    if (warp.is_usable()) {
        run_all(warp, "WARP");
    } else {
        std::cout << "WARP unavailable — skipped\n";
    }

    const GpuDevice hardware = GpuDevice::create(GpuDevicePreference::hardware_only);
    if (hardware.is_usable()) {
        run_all(hardware, hardware.capability().adapter.description.data());
    } else {
        std::cout << "hardware adapter unavailable — skipped\n";
    }

    if (failures != 0) {
        std::cerr << failures << " failure(s)\n";
        return 1;
    }
    std::cout << "gpu vibrance tests passed\n";
    return 0;
}
