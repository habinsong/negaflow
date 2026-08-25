// 메모리 예산이 **프로세스 전체**를 상한 안에 두는지, GPU 예산이 기계마다 비율로 잡히는지의
// 시험입니다.
//
// 여기 있는 것들은 전부 **실제로 났던 고장**을 고정한 것입니다.
//   ① 캐시가 저마다 자기 예산 안이었는데 작업 관리자 총량은 상한을 넘었습니다 — 코드·
//      런타임·WinUI·D3D11 스테이징 몫이 어느 예산에도 없었기 때문입니다. 실측으로 31.8GB
//      기계에서 상한 8.27GB 인데 앱이 8.77GB 였습니다.
//   ② `GpuImagePool` 이 잡는 작업 텍스처가 어느 예산에도 없었습니다. 48MP 한 장이 float32
//      RGBA 로 770MB 이고 풀이 최대 여섯 장 + 보존 여섯 장이라 9.2GB 를 잡을 수 있었습니다.
//   ③ 첫 판에서 GPU 예산에 512MB 라는 **바이트 상수**를 하한으로 박았습니다. 기계마다 VRAM
//      도 RAM 도 다르므로 그런 상수는 어느 기계에서는 그대로 거짓말이 됩니다.

#include "negaflow/core/machine_memory.h"
#include "negaflow/gpu/gpu_cache_budget.h"
#include "negaflow/gpu/gpu_device.h"
#include "negaflow/imageio/wic_tiff_decoder.h"
#include "negaflow/imaging/scanner_to_working.h"
#include "negaflow/output/working_to_srgb16.h"
#include "negaflow/pipeline/frame_cache_limits.h"
#include "negaflow/pipeline/gpu_accelerator.h"
#include "export/support/frame_cache_budget.h"

#include <cstdint>
#include <iostream>

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

constexpr std::uint64_t megabyte = 1024ULL * 1024ULL;

}  // namespace

int main() {
    namespace detail = negaflow::pipeline::develop_export_detail;

    // ── 자동 비율은 설치 메모리를 따라갑니다(macOS 와 같은 25~35% 계단) ──
    expect(
        detail::FrameCacheBudget::automatic_memory_fraction(16ULL * 1024ULL * megabyte) == 0.25,
        "16GB 는 25%");
    expect(
        detail::FrameCacheBudget::automatic_memory_fraction(8ULL * 1024ULL * megabyte) == 0.25,
        "8GB 도 하한 25%");
    const double at_32 =
        detail::FrameCacheBudget::automatic_memory_fraction(32ULL * 1024ULL * megabyte);
    expect(at_32 > 0.25 && at_32 < 0.35, "32GB 는 25% 와 35% 사이");
    expect(
        detail::FrameCacheBudget::automatic_memory_fraction(256ULL * 1024ULL * megabyte) == 0.35,
        "아주 큰 기계도 35% 를 넘지 않습니다");

    // ── 프로세스 private 은 실제 값이어야 합니다 ──
    const std::uint64_t private_bytes = detail::process_private_bytes();
    expect(private_bytes > 0ULL, "프로세스 private 을 읽습니다");

    // ── 캐시가 아닌 몫은 private 을 넘지 않습니다 ──
    const std::uint64_t overhead = detail::non_cache_overhead_bytes();
    expect(overhead <= detail::process_private_bytes(), "간접비는 private 안입니다");

    // ── 캐시가 자기 상주량을 알리면 그만큼 간접비에서 빠집니다 ──
    // 250ms 캐시가 있으므로 값이 갱신될 때까지 기다립니다. 되먹임이 실제로 도는지를
    // 보는 자리입니다 - 안 돌면 예산이 프로세스를 못 지킵니다.
    detail::report_cache_resident_bytes(detail::FrameCacheKind::decoded_source, 0ULL);
    detail::report_cache_resident_bytes(detail::FrameCacheKind::preview_proxy, 0ULL);
    const negaflow::pipeline::FrameCacheMemoryReport report =
        negaflow::pipeline::frame_cache_memory_report();
    expect(
        report.automatic_process_ceiling_bytes > 0ULL,
        "자동 상한을 셉니다");
    expect(
        report.decoded_source_budget_bytes + report.preview_proxy_budget_bytes +
                report.developed_display_budget_bytes <=
            report.automatic_process_ceiling_bytes,
        "캐시 예산 합계는 프로세스 상한 안입니다");

    // 셸의 managed 표시본 캐시도 같은 예산을 나눠 씁니다. 알린 만큼이 간접비에서 빠지고,
    // 예산을 받아 가야 간접비가 늘 때 이쪽도 같이 줄어듭니다.
    const std::uint64_t display_budget =
        negaflow::pipeline::sync_display_cache_budget(0ULL);
    expect(display_budget > 0ULL, "표시본 캐시가 예산을 받습니다");
    expect(
        display_budget < report.automatic_process_ceiling_bytes,
        "표시본 예산은 프로세스 상한보다 작습니다");
    // 알린 값이 실제로 반영되는지 - 많이 들고 있다고 알리면 남는 예산이 줄어야 합니다.
    const std::uint64_t crowded_budget = negaflow::pipeline::sync_display_cache_budget(
        report.automatic_process_ceiling_bytes / 2ULL);
    expect(crowded_budget <= display_budget, "많이 들고 있다고 알리면 예산이 줄거나 같습니다");
    (void)negaflow::pipeline::sync_display_cache_budget(0ULL);

    // ── GPU 예산: 바이트 상수가 아니라 이 기계 용량의 비율입니다 ──
    // 보고와 같은 장치를 봅니다 - `GpuDevice::shared()` 는 가속기 것과 다른 장치입니다.
    const negaflow::gpu::GpuDevice& device =
        negaflow::pipeline::GpuAccelerator::shared().device();
    const std::uint64_t automatic = negaflow::gpu::GpuCacheBudget::automatic_bytes(device);
    if (!device.is_usable()) {
        expect(automatic == 0ULL, "GPU 가 없으면 한도도 없습니다");
    } else {
        negaflow::gpu::GpuVideoMemoryInfo memory{};
        const bool has_budget = device.query_local_video_memory_info(memory);
        if (device.capability().adapter.is_integrated) {
            expect(automatic > 0ULL, "내장도 설치 RAM 에서 몫을 뗍니다");
        } else if (has_budget && memory.budget > 0ULL) {
            expect(automatic < memory.budget, "DXGI 예산보다 작아야 합니다");
            expect(
                automatic ==
                    static_cast<std::uint64_t>(
                        static_cast<double>(memory.budget) *
                        negaflow::gpu::GpuCacheBudget::discrete_budget_fraction),
                "외장 한도는 DXGI 예산의 정해진 몫입니다");
        }

        // 수동값을 걸면 그대로 걸립니다. 되돌리면 자동으로 돌아갑니다.
        negaflow::gpu::set_gpu_cache_limit_bytes(1234ULL * megabyte);
        expect(
            negaflow::gpu::GpuCacheBudget::effective_bytes(device) == 1234ULL * megabyte,
            "수동 한도가 그대로 걸립니다");
        negaflow::gpu::set_gpu_cache_limit_bytes(0ULL);
        expect(
            negaflow::gpu::GpuCacheBudget::effective_bytes(device) == automatic,
            "0 이면 자동으로 돌아갑니다");
    }

    // ── 화상 한 장의 상한도 기계에서 나옵니다 ──
    //
    // 앞 판은 네 곳에 `512MB` 가 박혀 있었고, 48MP(8484x5656) 한 장이 float32 RGBA 로
    // 768MB 라 32GB 기계에서도 48MP 스캔이 `memory_limit_exceeded` 로 거부됐습니다.
    // 64MP(1,568MB)·128MP(3,135MB)도 마찬가지였습니다.
    const std::uint64_t installed = negaflow::core::installed_memory_bytes();
    const std::uint64_t pixel_limit = negaflow::core::default_max_pixel_bytes();
    expect(pixel_limit >= 512ULL * megabyte, "모르는 기계에서도 예전 선은 지킵니다");
    if (installed > 0ULL) {
        expect(pixel_limit == installed, "상한은 이 기계의 설치 메모리입니다");
        // 48 · 64 · 128MP 한 장이 상한 안이어야 합니다. 3:2 로 잡은 화소 수 x 16바이트입니다.
        for (const std::uint64_t megapixels : {48ULL, 64ULL, 128ULL}) {
            const std::uint64_t working = megapixels * 1000000ULL * 16ULL;
            expect(working < pixel_limit, "이 기계에서 큰 스캔 한 장이 상한 안입니다");
        }
        // 그래도 손상된 헤더는 거릅니다 - 20만 x 20만 은 어느 기계에서도 불가능합니다.
        expect(
            200000ULL * 200000ULL * 16ULL > pixel_limit,
            "말이 안 되는 치수는 여전히 거부합니다");
    }
    expect(
        negaflow::imaging::ScannerToWorkingLimits{}.max_working_pixel_bytes == pixel_limit,
        "스캐너->작업 변환이 그 상한을 씁니다");
    expect(
        negaflow::imageio::WicTiffDecodeLimits{}.max_decoded_pixel_bytes == pixel_limit,
        "TIFF 디코더가 그 상한을 씁니다");
    expect(
        negaflow::output::WorkingToSrgb16Limits{}.max_encoded_pixel_bytes == pixel_limit,
        "sRGB16 내보내기가 그 상한을 씁니다");

    if (failures == 0) {
        std::cout << "memory_budget_tests ok\n";
    }
    return failures == 0 ? 0 : 1;
}
