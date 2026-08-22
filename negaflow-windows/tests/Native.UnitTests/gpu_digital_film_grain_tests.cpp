// CPU/GPU 동치 시험 — `digitalFilmGrainDensity`.
//
// **참조를 옮겨 적지 않습니다.** 진짜 CPU 함수 `apply_digital_film_grain_material` 을
// 그대로 부르고 그 결과와 겨룹니다.
//
// 시험 셋입니다:
// ① **해시 단독** — 좌표 해시는 전부 uint32 정수 연산이라 **delta 0** 을 요구합니다.
// float 오차가 낄 자리가 없으므로, 어긋나면 옮겨 적은 것이 틀린 것입니다.
// (`size <= 1.01` 로 두면 커널이 보간을 건너뛰고 해시를 그대로 냅니다. 진폭을 크게
// 주고 밝기를 0.18 로 고정하면 출력이 노이즈의 단조 함수라 해시를 되짚을 수 있습니다.)
// ② **전체 사슬** — 제품이 실제로 쓰는 `size`(1.10~1.60)로 보간 경로까지 돌려 `1e-5`.
// ③ **통계** — 노이즈 필드의 평균이 0 인지(DC 바이어스가 없는지). macOS 와 화소로
// 맞출 수 없다는 것이 1절의 결론이므로, 대조 항목은 화소가 아니라 이 통계입니다.

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <utility>
#include <vector>

#include "negaflow/gpu/gpu_device.h"
#include "negaflow/gpu/gpu_digital_film_grain.h"
#include "negaflow/gpu/gpu_working_image.h"
#include "negaflow/imaging/digital_film_grain.h"
#include "negaflow/imaging/digital_film_physics.h"

namespace {

using negaflow::core::Rgba32F;
using negaflow::gpu::GpuDevice;
using negaflow::gpu::GpuDevicePreference;
using negaflow::gpu::GpuDigitalFilmGrain;
using negaflow::gpu::GpuImageStatus;
using negaflow::gpu::GpuKernelStatus;
using negaflow::gpu::GpuWorkingImage;
using negaflow::imaging::DigitalFilmGrainProfile;
using negaflow::imaging::WorkingImage;

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

constexpr float tolerance = 1.0e-5F;
// 실제 스캔 폭에 가깝게 잡습니다 — 보간 좌표 `(x + 0.5) / size` 가 커질수록 float
// 양자화가 커지므로, 좁은 시험 이미지는 그 오차를 숨깁니다.
constexpr std::uint32_t width = 1024U;
constexpr std::uint32_t height = 96U;

[[nodiscard]] std::vector<Rgba32F> make_pattern() {
    std::vector<Rgba32F> pixels(static_cast<std::size_t>(width) * height);
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const std::uint32_t seed = (x * 73856093U) ^ (y * 19349663U);
            const std::uint32_t mixed = (seed ^ (seed >> 13U)) * 1274126177U;
            const float noise = static_cast<float>(mixed >> 8U) / 16777216.0F;
            // 암부(밀도 2 대)부터 명부(밀도 −0.7)까지 전 구간을 지나가게 합니다 —
            // 밀도 응답의 `physical`·`perceptual` 두 인자가 밝기마다 다른 자리를 씁니다.
            const float base = 0.0015F + (static_cast<float>(x) / static_cast<float>(width));
            pixels[(static_cast<std::size_t>(y) * width) + x] = Rgba32F{
                base,
                std::max(base * 0.72F + (noise * 0.03F), 1.0e-4F),
                std::max(base * 0.51F, 1.0e-4F),
                0.25F + (0.5F * noise)};
        }
    }
    return pixels;
}

[[nodiscard]] WorkingImage make_working_image(const std::vector<Rgba32F>& pixels) {
    WorkingImage image{};
    image.width = width;
    image.height = height;
    image.stride_pixels = width;
    image.pixels = pixels;
    return image;
}

// GPU 한 번 돌리고 결과를 돌려줍니다. 실패하면 비어 있습니다.
[[nodiscard]] std::vector<Rgba32F> run_gpu(
    const GpuDevice& device,
    const std::vector<Rgba32F>& pixels,
    const GpuDigitalFilmGrain::Parameters& parameters) {
    GpuDigitalFilmGrain kernel{};
    if (GpuDigitalFilmGrain::create(device, kernel) != GpuKernelStatus::ok) {
        expect(false, "grain kernel must be creatable");
        return {};
    }
    GpuWorkingImage source{};
    GpuWorkingImage destination{};
    if (GpuWorkingImage::upload(device, pixels.data(), width, height, width, source) !=
            GpuImageStatus::ok ||
        GpuWorkingImage::create(device, width, height, destination) != GpuImageStatus::ok) {
        expect(false, "grain images must be creatable");
        return {};
    }
    if (kernel.dispatch(device, source, destination, parameters) != GpuKernelStatus::ok) {
        expect(false, "grain dispatch must succeed");
        return {};
    }
    std::vector<Rgba32F> output(pixels.size());
    if (destination.download(device, output.data(), width) != GpuImageStatus::ok) {
        expect(false, "grain download must succeed");
        return {};
    }
    return output;
}

// 두 결과의 최대 오차. 알파까지 봅니다 — 커널이 알파를 건드리면 여기서 걸립니다.
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

void grain_matches_cpu(
    const GpuDevice& device,
    const char* const label,
    const DigitalFilmGrainProfile& profile,
    const float expected_tolerance) {
    const std::vector<Rgba32F> pixels = make_pattern();
    constexpr double strength = 0.85;

    auto cpu = negaflow::imaging::apply_digital_film_grain_material(
        make_working_image(pixels), profile, strength);
    expect(
        cpu.status == negaflow::imaging::DigitalFilmGrainStatus::ok,
        "CPU grain must succeed");
    expect(cpu.info.applied, "CPU grain must actually apply");

    const GpuDigitalFilmGrain::Parameters parameters =
        GpuDigitalFilmGrain::resolve(profile, strength);
    expect(parameters.applied, "GPU resolve must agree that grain applies");
    const std::vector<Rgba32F> gpu = run_gpu(device, pixels, parameters);
    if (gpu.empty()) {
        return;
    }

    const float worst = max_delta(cpu.image.pixels, gpu);
    if (worst > expected_tolerance) {
        std::cerr << "FAIL: " << label << " grain delta " << worst << " exceeds "
                  << expected_tolerance << '\n';
        ++failures;
    } else {
        std::cout << label << " grain max delta " << worst << '\n';
    }
}

// ① 해시 단독. `size <= 1.01` 이면 보간을 건너뛰므로 부동소수가 낄 자리가 해시 뒤
// 밀도 응답뿐입니다. 밝기를 정확히 0.18 로 두면 밀도가 0 이라 응답이 노이즈에만
// 의존하고, CPU 와 **같은 초월함수 입력**을 받습니다.
void hash_field_matches_cpu_exactly(const GpuDevice& device, const char* const label) {
    std::vector<Rgba32F> pixels(static_cast<std::size_t>(width) * height);
    for (Rgba32F& pixel : pixels) {
        pixel = Rgba32F{0.18F, 0.18F, 0.18F, 1.0F};
    }
    const DigitalFilmGrainProfile profile{0.5, 1.0, 1.0};
    constexpr double strength = 1.0;

    auto cpu = negaflow::imaging::apply_digital_film_grain_material(
        make_working_image(pixels), profile, strength);
    expect(
        cpu.status == negaflow::imaging::DigitalFilmGrainStatus::ok,
        "CPU hash-only grain must succeed");

    const std::vector<Rgba32F> gpu =
        run_gpu(device, pixels, GpuDigitalFilmGrain::resolve(profile, strength));
    if (gpu.empty()) {
        return;
    }
    // 여기서도 `pow`/`exp` 가 한 번씩 돌아 마지막 비트는 다를 수 있습니다. 요구하는 것은
    // **해시가 같다**는 것이고, 해시가 다르면 오차가 1e-5 가 아니라 0.0x 로 나옵니다.
    const float worst = max_delta(cpu.image.pixels, gpu);
    if (worst > tolerance) {
        std::cerr << "FAIL: " << label << " hash-only grain delta " << worst
                  << " — coordinate hash disagrees\n";
        ++failures;
    } else {
        std::cout << label << " hash-only grain max delta " << worst << '\n';
    }
}

// ③ 노이즈 필드의 평균이 0 인가. 진폭을 0 으로 두면 출력이 입력과 같아야 하고,
// 진폭을 켜면 밀도 변화의 평균이 0 근처여야 합니다 — DC 바이어스가 있으면
// 그레인을 켤 때마다 이미지가 밝아지거나 어두워집니다.
void grain_has_no_dc_bias(const GpuDevice& device, const char* const label) {
    std::vector<Rgba32F> pixels(static_cast<std::size_t>(width) * height);
    for (Rgba32F& pixel : pixels) {
        pixel = Rgba32F{0.18F, 0.18F, 0.18F, 1.0F};
    }
    const DigitalFilmGrainProfile profile{0.30, 1.0, 1.15};
    const std::vector<Rgba32F> gpu =
        run_gpu(device, pixels, GpuDigitalFilmGrain::resolve(profile, 1.0));
    if (gpu.empty()) {
        return;
    }
    double sum = 0.0;
    for (const Rgba32F& pixel : gpu) {
        // 밀도 도메인으로 되돌려 봅니다 — 노이즈가 더해지는 자리가 거기입니다.
        sum += -std::log10(static_cast<double>(pixel.red) / 0.18);
    }
    const double mean = sum / static_cast<double>(gpu.size());
    if (std::abs(mean) > 2.0e-3) {
        std::cerr << "FAIL: " << label << " grain density mean " << mean
                  << " — noise field has DC bias\n";
        ++failures;
    } else {
        std::cout << label << " grain density mean " << mean << '\n';
    }
}

void run_all(const GpuDevice& device, const char* const label) {
    hash_field_matches_cpu_exactly(device, label);
    // 제품 표(`digital_film_physics.cpp`)의 실제 값 범위입니다 — 가장 작은 크기와
    // 가장 큰 크기 둘 다 돌립니다. **전부 1.01 을 넘으므로 보간 경로가 제품 경로입니다.**
    grain_matches_cpu(device, label, DigitalFilmGrainProfile{0.026, 0.34, 1.10}, tolerance);
    grain_matches_cpu(device, label, DigitalFilmGrainProfile{0.034, 0.46, 1.60}, tolerance);
    // 채도 0 — 휘도 노이즈만 남는 경로.
    grain_matches_cpu(device, label, DigitalFilmGrainProfile{0.030, 0.0, 1.25}, tolerance);
    grain_has_no_dc_bias(device, label);
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
    std::cout << "gpu digital film grain tests passed\n";
    return 0;
}
