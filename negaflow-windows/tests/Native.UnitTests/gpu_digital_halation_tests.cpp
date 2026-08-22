// CPU/GPU 동치 시험 — `digitalHalation`.
//
// **참조를 옮겨 적지 않습니다.** 진짜 CPU 함수 `apply_digital_halation_material` 을
// 그대로 부르고 그 결과와 겨룹니다.
//
// 주의 CPU 는 512px 타일로 돌지만 GPU 는 전체를 한 번에 돕니다. `film_scan_denoise` 와 달리
// **여기는 그래도 됩니다** — 이 가우시안은 직접 컨볼루션이라 러닝 섬의 누적 이력이
// 없습니다. 그 주장을 시험하려고 폭을 타일 한 변(512)보다 크게 잡습니다.
//
// 주의 가중치 식이 `film_scan_denoise` 와 **다릅니다.** Core Image 분산 보정 0.08 이 없고
// 지수·합계를 `double` 로 굴립니다(`digital_halation.cpp:51`). GPU 도 그 식을 씁니다
// (`GpuGaussianBlur::weights_for_halation_sigma`). 섞으면 값이 갈립니다.

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <utility>
#include <vector>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_digital_halation.h"
#include "negaflow/gpu/gpu_neighborhood.h"
#include "negaflow/gpu/gpu_working_image.h"
#include "negaflow/imaging/digital_halation.h"
#include "negaflow/imaging/digital_film_physics.h"

namespace {

using negaflow::core::Rgba32F;
using negaflow::gpu::GpuDevice;
using negaflow::gpu::GpuDevicePreference;
using negaflow::gpu::GpuDigitalHalation;
using negaflow::gpu::GpuGaussianBlur;
using negaflow::gpu::GpuImageStatus;
using negaflow::gpu::GpuKernelStatus;
using negaflow::gpu::GpuWorkingImage;
using negaflow::imaging::DigitalHalationMaterial;
using negaflow::imaging::WorkingImage;

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

constexpr float tolerance = 1.0e-5F;
// 타일 한 변이 512 입니다. 그보다 크게 잡아 경계를 지나가게 합니다.
constexpr std::uint32_t width = 600U;
constexpr std::uint32_t height = 96U;

// 헐레이션이 실제로 보이도록 밝은 점과 어두운 바탕을 섞습니다.
[[nodiscard]] std::vector<Rgba32F> make_pattern() {
    std::vector<Rgba32F> pixels(static_cast<std::size_t>(width) * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const std::uint32_t seed = (x * 73856093U) ^ (y * 19349663U);
            const std::uint32_t mixed = (seed ^ (seed >> 13U)) * 1274126177U;
            const float noise = static_cast<float>(mixed >> 8U) / 16777216.0F;
            const bool spot = ((x / 37U) + (y / 23U)) % 5U == 0U;
            const float base = spot ? 0.95F : (0.05F + noise * 0.10F);
            pixels[(static_cast<std::size_t>(y) * width) + x] = Rgba32F{
                base,
                std::clamp(base * 0.8F + noise * 0.05F, 0.0F, 1.0F),
                std::clamp(base * 0.55F, 0.0F, 1.0F),
                0.3F + 0.5F * noise};
        }
    }
    return pixels;
}

void halation_matches_cpu(const GpuDevice& device, const char* const label) {
    GpuGaussianBlur gaussian{};
    GpuDigitalHalation halation{};
    if (GpuGaussianBlur::create(device, gaussian) != GpuKernelStatus::ok ||
        GpuDigitalHalation::create(device, halation) != GpuKernelStatus::ok) {
        expect(false, "halation kernels must be creatable");
        return;
    }

    const std::vector<Rgba32F> source = make_pattern();

    struct Case final {
        DigitalHalationMaterial material;
        double strength;
        const char* what;
    };
    // 실제 필름 프로파일에서 재료를 가져옵니다 — 숫자를 지어내지 않습니다.
    const auto* const physics =
        negaflow::imaging::digital_film_physics(negaflow::imaging::FilmEmulation::portra_400);
    if (physics == nullptr) {
        expect(false, "a real film physics entry must exist");
        return;
    }
    const DigitalHalationMaterial real{
        physics->scatter_strength, physics->halation_strength, physics->halation_radius_ratio};

    const Case cases[] = {
        {real, 1.0, "portra400 full"},
        {real, 0.35, "portra400 partial"},
        // 조기 반환 자리 — 세기가 임계 아래면 CPU 는 원본을 그대로 냅니다.
        {real, 0.0005, "below identity threshold"},
        // 반경 비율 0 도 조기 반환입니다.
        {{{{0.2, 0.1, 0.05}}, {{0.3, 0.1, 0.02}}, 0.0}, 1.0, "zero radius ratio"},
    };

    for (const Case& item : cases) {
        WorkingImage cpu_image{};
        cpu_image.width = width;
        cpu_image.height = height;
        cpu_image.stride_pixels = width;
        cpu_image.pixels = source;
        const auto cpu = negaflow::imaging::apply_digital_halation_material(
            std::move(cpu_image), item.material, item.strength);
        if (cpu.status != negaflow::imaging::DigitalHalationStatus::ok) {
            expect(false, "the CPU oracle must succeed");
            continue;
        }

        GpuWorkingImage input{};
        GpuWorkingImage output{};
        GpuWorkingImage scratch[GpuDigitalHalation::scratch_count]{};
        if (GpuWorkingImage::upload(device, source.data(), width, height, width, input) !=
                GpuImageStatus::ok ||
            GpuWorkingImage::create(device, width, height, output) != GpuImageStatus::ok) {
            expect(false, "halation images must be creatable");
            return;
        }
        for (GpuWorkingImage& image : scratch) {
            if (GpuWorkingImage::create(device, width, height, image) != GpuImageStatus::ok) {
                expect(false, "halation scratch must be creatable");
                return;
            }
        }

        const GpuDigitalHalation::Parameters parameters =
            GpuDigitalHalation::resolve(item.material, item.strength, width, height);
        // GPU 의 조기 반환 판정이 CPU 와 같아야 합니다 — 다르면 한쪽만 커널을 돕니다.
        expect(
            parameters.applied == cpu.info.applied,
            "the GPU early return must agree with the CPU");

        if (halation.dispatch(device, gaussian, input, scratch, output, parameters) !=
            GpuKernelStatus::ok) {
            expect(false, "halation dispatch must succeed");
            continue;
        }
        std::vector<Rgba32F> gpu_pixels(source.size());
        if (output.download(device, gpu_pixels.data(), width) != GpuImageStatus::ok) {
            expect(false, "halation download must succeed");
            continue;
        }

        float worst = 0.0F;
        float worst_alpha = 0.0F;
        std::size_t worst_index = 0U;
        for (std::size_t index = 0U; index < gpu_pixels.size(); ++index) {
            const Rgba32F& reference = cpu.image.pixels[index];
            const float largest = std::max(
                std::abs(reference.red - gpu_pixels[index].red),
                std::max(
                    std::abs(reference.green - gpu_pixels[index].green),
                    std::abs(reference.blue - gpu_pixels[index].blue)));
            if (largest > worst) {
                worst = largest;
                worst_index = index;
            }
            worst_alpha =
                std::max(worst_alpha, std::abs(reference.alpha - gpu_pixels[index].alpha));
        }

        if (worst > tolerance) {
            std::cerr << "FAIL: " << label << ' ' << item.what << " max delta " << worst
                      << " at (" << (worst_index % width) << ',' << (worst_index / width)
                      << ")\n";
            ++failures;
        } else {
            std::cout << "[gpu] " << label << ' ' << item.what << " max delta " << worst << '\n';
        }
        // 알파는 CPU 가 손대지 않습니다 — 비트까지 그대로여야 합니다.
        expect(worst_alpha == 0.0F, "alpha is preserved exactly");
    }
}

} // namespace

int main() {
    const GpuDevice warp = GpuDevice::create(GpuDevicePreference::warp_only);
    if (!warp.is_usable()) {
        std::cerr << "FAIL: WARP device is required for these checks\n";
        return 1;
    }
    halation_matches_cpu(warp, "warp");

    const GpuDevice hardware = GpuDevice::create(GpuDevicePreference::hardware_only);
    if (hardware.is_usable()) {
        std::cout << "[gpu] hardware: " << hardware.capability().adapter.description.data() << '\n';
        halation_matches_cpu(hardware, "hardware");
    } else {
        std::cout << "[gpu] hardware absent, WARP only\n";
    }

    if (failures != 0) {
        std::cerr << failures << " gpu halation check(s) failed\n";
        return 1;
    }
    std::cout << "gpu halation checks passed\n";
    return 0;
}
