// CPU/GPU 동치 시험 — 형태학(열기·닫기·양극 톱햇).
//
// ☠️ **참조를 옮겨 적지 않습니다.** 진짜 CPU 함수 `grain_mend_detail::opening` ·
//    `closing` · `bipolar_top_hat` 을 그대로 부르고 그 결과와 겨룹니다.
//    (`grain_mend_morphology.h` 는 private 헤더라 시험 대상에 그 경로를 답니다.)
//
// ☠️ 여기는 **허용 오차가 아니라 0 을 요구합니다.** min/max 는 창 안에서 하나를 고르는
//    일이라 부동소수 산술이 없습니다 — CPU 의 단조 덱(vHGW)과 GPU 의 직접 훑기가
//    같은 값을 골라야 합니다. 1 ulp 라도 다르면 그것은 반올림이 아니라 **다른 값을 고른
//    것**이고, 이식이 틀린 것입니다.
//
// GPU 는 네 채널을 독립으로 돌리므로, CPU 판 넷을 한 텍스처에 담아 한 번에 겨룹니다 —
// 검출이 채널 셋 + 휘도를 다루는 실제 모양과 같습니다.

#include "grain_mend_morphology.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <vector>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_morphology.h"
#include "negaflow/gpu/gpu_working_image.h"

namespace {

using negaflow::core::Rgba32F;
using negaflow::gpu::GpuDevice;
using negaflow::gpu::GpuDevicePreference;
using negaflow::gpu::GpuImageStatus;
using negaflow::gpu::GpuKernelStatus;
using negaflow::gpu::GpuMorphology;
using negaflow::gpu::GpuWorkingImage;
namespace morphology = negaflow::imaging::grain_mend_detail;

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

// 스레드 그룹 8 의 배수가 아닌 값으로 경계를 봅니다.
constexpr std::uint32_t width = 77U;
constexpr std::uint32_t height = 53U;

// 먼지·흠집처럼 고립된 밝은/어두운 점과 평탄한 면, 경계를 섞습니다.
[[nodiscard]] std::array<std::vector<float>, 4U> make_planes() {
    std::array<std::vector<float>, 4U> planes{};
    for (std::size_t channel = 0U; channel < planes.size(); ++channel) {
        planes[channel].resize(static_cast<std::size_t>(width) * height);
        for (std::uint32_t y = 0U; y < height; ++y) {
            for (std::uint32_t x = 0U; x < width; ++x) {
                const std::uint32_t seed =
                    (x * 73856093U) ^ (y * 19349663U) ^ (static_cast<std::uint32_t>(channel) * 83492791U);
                const std::uint32_t mixed = (seed ^ (seed >> 13U)) * 1274126177U;
                const float noise = static_cast<float>(mixed >> 8U) / 16777216.0F;
                const bool speck = ((x * 5U) + (y * 3U) + static_cast<std::uint32_t>(channel)) % 89U == 0U;
                const bool hole = ((x * 11U) + (y * 7U)) % 131U == 0U;
                const float ramp = static_cast<float>(y) / static_cast<float>(height - 1U);
                float value = 0.25F + ramp * 0.4F + (noise - 0.5F) * 0.08F;
                if (speck) {
                    value = 0.98F;
                }
                if (hole) {
                    value = 0.02F;
                }
                planes[channel][(static_cast<std::size_t>(y) * width) + x] =
                    std::clamp(value, 0.0F, 1.0F);
            }
        }
    }
    return planes;
}

[[nodiscard]] std::vector<Rgba32F> pack(const std::array<std::vector<float>, 4U>& planes) {
    std::vector<Rgba32F> pixels(planes[0].size());
    for (std::size_t index = 0U; index < pixels.size(); ++index) {
        pixels[index] = {
            planes[0][index], planes[1][index], planes[2][index], planes[3][index]};
    }
    return pixels;
}

// 채널마다 CPU 판을 돌려 묶은 것과 GPU 결과를 겨룹니다.
[[nodiscard]] float compare(
    const std::array<std::vector<float>, 4U>& reference,
    const std::vector<Rgba32F>& measured) noexcept {
    float worst = 0.0F;
    for (std::size_t index = 0U; index < measured.size(); ++index) {
        worst = std::max(worst, std::abs(reference[0][index] - measured[index].red));
        worst = std::max(worst, std::abs(reference[1][index] - measured[index].green));
        worst = std::max(worst, std::abs(reference[2][index] - measured[index].blue));
        worst = std::max(worst, std::abs(reference[3][index] - measured[index].alpha));
    }
    return worst;
}

enum class Operation { opening, closing, top_hat };

[[nodiscard]] const char* operation_name(const Operation operation) noexcept {
    switch (operation) {
        case Operation::opening: return "opening";
        case Operation::closing: return "closing";
        case Operation::top_hat: return "bipolar top hat";
    }
    return "unknown";
}

void morphology_matches_cpu(const GpuDevice& device, const char* const label) {
    GpuMorphology kernel{};
    if (GpuMorphology::create(device, kernel) != GpuKernelStatus::ok) {
        expect(false, "morphology kernel must be creatable");
        return;
    }

    const std::array<std::vector<float>, 4U> planes = make_planes();
    const std::vector<Rgba32F> packed = pack(planes);

    GpuWorkingImage source{};
    GpuWorkingImage destination{};
    GpuWorkingImage scratch[GpuMorphology::top_hat_scratch_count]{};
    if (GpuWorkingImage::upload(device, packed.data(), width, height, width, source) !=
            GpuImageStatus::ok ||
        GpuWorkingImage::create(device, width, height, destination) != GpuImageStatus::ok) {
        expect(false, "morphology images must be creatable");
        return;
    }
    for (GpuWorkingImage& image : scratch) {
        if (GpuWorkingImage::create(device, width, height, image) != GpuImageStatus::ok) {
            expect(false, "morphology scratch must be creatable");
            return;
        }
    }

    // 실제로 쓰이는 반경 전부입니다 — 검출 먼지 {4, 8, 12}(`grain_mend_detector.cpp:154`),
    // 미세 입자 {1, 3}(`grain_mend_speck_detector.cpp:17`), 그리고 조기 반환 0.
    const std::uint32_t radii[] = {0U, 1U, 3U, 4U, 8U, 12U};
    const Operation operations[] = {Operation::opening, Operation::closing, Operation::top_hat};

    for (const Operation operation : operations) {
        for (const std::uint32_t radius : radii) {
            std::array<std::vector<float>, 4U> reference{};
            for (std::size_t channel = 0U; channel < reference.size(); ++channel) {
                switch (operation) {
                    case Operation::opening:
                        reference[channel] =
                            morphology::opening(planes[channel], width, height, radius);
                        break;
                    case Operation::closing:
                        reference[channel] =
                            morphology::closing(planes[channel], width, height, radius);
                        break;
                    case Operation::top_hat:
                        reference[channel] =
                            morphology::bipolar_top_hat(planes[channel], width, height, radius);
                        break;
                }
            }

            GpuKernelStatus status = GpuKernelStatus::invalid_arguments;
            switch (operation) {
                case Operation::opening:
                    status = kernel.opening(device, source, scratch, destination, radius);
                    break;
                case Operation::closing:
                    status = kernel.closing(device, source, scratch, destination, radius);
                    break;
                case Operation::top_hat:
                    status = kernel.bipolar_top_hat(device, source, scratch, destination, radius);
                    break;
            }
            if (status != GpuKernelStatus::ok) {
                expect(false, "morphology dispatch must succeed");
                continue;
            }

            std::vector<Rgba32F> gpu_pixels(packed.size());
            if (destination.download(device, gpu_pixels.data(), width) != GpuImageStatus::ok) {
                expect(false, "morphology download must succeed");
                continue;
            }

            const float worst = compare(reference, gpu_pixels);
            // ☠️ 선택 연산이므로 **정확히 0** 이어야 합니다.
            if (worst != 0.0F) {
                std::cerr << "FAIL: " << label << ' ' << operation_name(operation) << " radius "
                          << radius << " max delta " << worst << " (must be exactly 0)\n";
                ++failures;
            } else {
                std::cout << "[gpu] " << label << ' ' << operation_name(operation) << " radius "
                          << radius << " max delta 0\n";
            }
        }
    }

    // 같은 자원을 두 역할로 넘기면 D3D11 이 조용히 무시합니다. 거절해야 합니다.
    expect(
        kernel.opening(device, source, scratch, scratch[0], 4U) ==
            GpuKernelStatus::invalid_arguments,
        "scratch and destination must differ");
    expect(
        kernel.opening(device, source, nullptr, destination, 4U) ==
            GpuKernelStatus::invalid_arguments,
        "a null scratch array is rejected");
}

}  // namespace

int main() {
    const GpuDevice warp = GpuDevice::create(GpuDevicePreference::warp_only);
    if (!warp.is_usable()) {
        std::cerr << "FAIL: WARP device is required for these checks\n";
        return 1;
    }
    morphology_matches_cpu(warp, "warp");

    const GpuDevice hardware = GpuDevice::create(GpuDevicePreference::hardware_only);
    if (hardware.is_usable()) {
        std::cout << "[gpu] hardware: " << hardware.capability().adapter.description.data() << '\n';
        morphology_matches_cpu(hardware, "hardware");
    } else {
        std::cout << "[gpu] hardware absent, WARP only\n";
    }

    if (failures != 0) {
        std::cerr << failures << " gpu morphology check(s) failed\n";
        return 1;
    }
    std::cout << "gpu morphology checks passed\n";
    return 0;
}
