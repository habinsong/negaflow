// 현상 사슬이 GPU 에 머무는 동안에도 GPU 캐시 상한(자동·수동)을 지키는지 봅니다.
//
// 타깃 그레이드·노리츠 텍스처는 화상이 GPU 에 머문 채로 돕니다(`gpu_accelerator_color.cpp`).
// 상한 때문에 텍스처를 못 잡으면 화상을 내리고 CPU 로 물러나야 하는데, 그때 **낡은 호스트
// 화소**(반전 전 네거티브)를 쓰면 결과가 통째로 달라집니다. 그래서 상한을 셋으로 바꿔 가며
// 같은 사진을 현상하고 결과를 서로 대봅니다.
//   ① 자동 상한       — 사슬 전체가 GPU
//   ② 반전용 두 장만  — 반전은 GPU, 노리츠 텍스처(세 장 필요)에서 CPU 로 물러남
//   ③ 거의 0         — 전부 CPU
// GPU·CPU 판은 근사가 달라 비트 단위로는 다르지만 평균 차이는 1 단계 안팎입니다. 낡은
// 화소를 쓰면 평균 차이가 수십 단계로 벌어집니다.

#include "negaflow/gpu/gpu_cache_budget.h"
#include "negaflow/pipeline/develop_export.h"
#include "negaflow/pipeline/gpu_accelerator.h"
#include "synthetic_wic_tiff.h"

#include <cmath>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <vector>

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

constexpr std::uint32_t width = 512U;
constexpr std::uint32_t height = 384U;
constexpr std::uint32_t box = 1024U;

[[nodiscard]] negaflow::pipeline::DevelopExportRequest noritsu_request(
    const std::filesystem::path& source) {
    negaflow::pipeline::DevelopExportRequest request{};
    request.source = source;
    request.film_polarity = negaflow::pipeline::FilmPolarity::negative;
    request.base_estimation_mode = negaflow::pipeline::NegativeBaseEstimationMode::manual;
    request.negative.dmin = {0.18F, 0.11F, 0.08F};
    request.develop_target = negaflow::pipeline::DevelopTarget::noritsu;
    request.retain_preview_raw = false;
    return request;
}

[[nodiscard]] bool render(
    const std::filesystem::path& source,
    std::vector<std::uint8_t>& pixels) {
    pixels.assign(static_cast<std::size_t>(box) * box * 4U, 0U);
    return negaflow::pipeline::develop_preview(
               noritsu_request(source), box, box, pixels.data(), pixels.size())
        .succeeded;
}

[[nodiscard]] double mean_difference(
    const std::vector<std::uint8_t>& a,
    const std::vector<std::uint8_t>& b) {
    double sum = 0.0;
    std::uint64_t count = 0U;
    for (std::uint32_t y = 0U; y < height; ++y) {
        for (std::uint32_t x = 0U; x < width; ++x) {
            const std::size_t at = (static_cast<std::size_t>(y) * box + x) * 4U;
            for (std::size_t c = 0U; c < 3U; ++c) {
                sum += std::abs(static_cast<int>(a[at + c]) - static_cast<int>(b[at + c]));
                ++count;
            }
        }
    }
    return count == 0U ? 0.0 : sum / static_cast<double>(count);
}

}  // namespace

int main() {
    auto& accelerator = negaflow::pipeline::GpuAccelerator::shared();
    if (!accelerator.available()) {
        std::cout << "gpu_resident_budget skipped: no GPU (hardware or WARP)\n";
        return 0;
    }
    const std::filesystem::path source =
        std::filesystem::temp_directory_path() / "negaflow_gpu_resident_budget.tiff";
    {
        const std::vector<std::uint8_t> tiff =
            negaflow::test_fixtures::make_uncompressed_rgb16_defect_tiff(width, height);
        std::ofstream out(source, std::ios::binary | std::ios::trunc);
        out.write(reinterpret_cast<const char*>(tiff.data()), static_cast<std::streamsize>(tiff.size()));
        if (!out.good()) {
            std::cerr << "FAIL: could not write the test source\n";
            return 1;
        }
    }

    // ① 자동 상한.
    negaflow::gpu::set_gpu_cache_limit_bytes(0U);
    std::vector<std::uint8_t> gpu_chain{};
    expect(render(source, gpu_chain), "automatic GPU cache limit renders");
    const std::uint64_t automatic =
        negaflow::gpu::GpuCacheBudget::effective_bytes(accelerator.device());
    expect(
        automatic == 0U || negaflow::gpu::gpu_pool_resident_bytes() <= automatic,
        "the pool stays within the automatic GPU cache limit");

    // ② 반전용 두 장만. 풀은 RGBA32F 이므로 한 장이 width*height*16 바이트입니다.
    const std::uint64_t two_images = static_cast<std::uint64_t>(width) * height * 16U * 2U;
    negaflow::gpu::set_gpu_cache_limit_bytes(two_images);
    std::vector<std::uint8_t> partial{};
    expect(render(source, partial), "a limit that fits only the inversion still renders");
    expect(
        negaflow::gpu::gpu_pool_resident_bytes() <= two_images,
        "lowering the manual GPU cache limit shrinks the pool to it");
    const double partial_difference = mean_difference(gpu_chain, partial);
    expect(
        partial_difference < 3.0,
        "falling back to the CPU mid-chain reads the current pixels, not the negative");

    // ③ 거의 0.
    negaflow::gpu::set_gpu_cache_limit_bytes(1U);
    std::vector<std::uint8_t> cpu_chain{};
    expect(render(source, cpu_chain), "a limit that fits nothing renders on the CPU");
    expect(
        negaflow::gpu::gpu_pool_resident_bytes() <= 1U,
        "a near-zero manual limit leaves no pool texture resident");
    const double cpu_difference = mean_difference(gpu_chain, cpu_chain);
    expect(cpu_difference < 3.0, "the CPU chain matches the GPU chain within rounding");

    negaflow::gpu::set_gpu_cache_limit_bytes(0U);
    std::error_code ignored{};
    std::filesystem::remove(source, ignored);
    std::cout << "gpu_resident_budget partial=" << partial_difference
              << " cpu=" << cpu_difference << (failures == 0 ? " ok" : " FAILED") << '\n';
    return failures == 0 ? 0 : 1;
}
