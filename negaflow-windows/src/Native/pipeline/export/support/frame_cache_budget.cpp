#include "frame_cache_budget.h"

#include "negaflow/gpu/gpu_cache_budget.h"
#include "negaflow/gpu/gpu_device.h"
#include "negaflow/pipeline/gpu_accelerator.h"
#include "negaflow/pipeline/frame_cache_limits.h"

#include <windows.h>

#include <psapi.h>

#include <algorithm>
#include <atomic>
#include <chrono>

namespace {

// 설정 창이 건 상주 한도입니다. 0 은 자동입니다. 캐시는 여러 스레드에서 들어오므로 원자로
// 둡니다 — 값 두 개뿐이라 잠금까지는 필요 없고, 조금 늦게 반영돼도 다음 축출에서 맞습니다.
// 예산 함수와 설정 함수가 서로 다른 이름공간에 있어 파일 맨 위에 둡니다.
std::atomic<std::uint32_t> g_manual_cleaned_raw_frames{0U};
std::atomic<std::uint32_t> g_manual_developed_frames{0U};

// 각 캐시가 알린 상주량입니다. 예산이 "캐시가 아닌 몫" 을 빼려면 이 값이 필요합니다.
std::atomic<std::uint64_t> g_cache_resident_bytes[3]{};

}  // namespace

namespace negaflow::pipeline::develop_export_detail {
namespace {

// macOS 는 8GB 이하에서 최소 한도(cleanedRaw 2 · developed 3)로 내려앉습니다
// (`FrameCacheBudget.automaticLimits`). 그 자리를 바이트로 옮긴 값입니다 —
// 개수 한도가 아니라 예산이므로, macOS 가 그 경우 허용하는 상주량을 그대로 적습니다.
constexpr double conservative_cleaned_raw_megabytes =
    2.0 * FrameCacheBudget::cleaned_raw_megabytes_per_frame;
constexpr double conservative_developed_megabytes =
    3.0 * FrameCacheBudget::developed_megabytes_per_frame;

constexpr double megabyte = 1024.0 * 1024.0;

// macOS `unitMegabytes` — 한 "단위"(cleaned raw 1 + developed 2)의 비용.
constexpr double unit_megabytes =
    FrameCacheBudget::cleaned_raw_megabytes_per_frame +
    static_cast<double>(FrameCacheBudget::developed_per_cleaned_raw) *
        FrameCacheBudget::developed_megabytes_per_frame;

constexpr double cleaned_raw_share =
    FrameCacheBudget::cleaned_raw_megabytes_per_frame / unit_megabytes;

// macOS의 developed 170MiB에는 정착 raw와 최종 표시 이미지가 함께 들어 있습니다.
// Windows는 둘을 native Rgba32F(16 B/px)와 managed BGRA8(4 B/px)로 따로 소유하므로,
// native가 developed 몫 전체를 다시 쓰지 않게 실제 화소 바이트 비율로 나눕니다.
constexpr double native_preview_proxy_share = 16.0 / (16.0 + 4.0);

[[nodiscard]] std::uint64_t bytes_from_megabytes(const double megabytes) noexcept {
    return megabytes <= 0.0
        ? 0ULL
        : static_cast<std::uint64_t>(megabytes * megabyte);
}

// 자동 예산 전체(바이트). 설치 메모리를 못 읽으면 macOS 의 보수 자리로 갑니다.
//
// macOS 의 25~35% 는 **사진 여러 장을 합친** 크기입니다 — 이 기계에서 cleaned raw 16장 +
// developed 32장. 장당으로 치면 ~180MB 입니다. 사진 한 장이 GB 단위를 먹는다면 그것은
// 예산이 큰 것이 아니라 **어딘가 새는 것**이고, 예산을 깎아 덮으면 원인이 남습니다.
[[nodiscard]] double automatic_budget_megabytes() noexcept {
    const std::uint64_t physical = FrameCacheBudget::physical_memory_bytes();
    if (physical == 0ULL ||
        physical <= FrameCacheBudget::conservative_memory_ceiling_bytes) {
        return conservative_cleaned_raw_megabytes + conservative_developed_megabytes;
    }
    const double total_megabytes = static_cast<double>(physical) / megabyte;
    const double share =
        total_megabytes * FrameCacheBudget::automatic_memory_fraction(physical);

    // **자동 상한은 프로세스 전체의 상한입니다.**
    //
    // 예전에는 이 몫을 캐시들끼리만 나눠 가졌습니다. 그런데 프로세스는 코드(실측 432MB)·
    // .NET 힙·WinUI·D3D11 스테이징(실측 297MB)·일회성 작업 버퍼도 들고 있고, 그 어느 것도
    // 어느 예산에도 없었습니다. 그래서 캐시가 전부 자기 예산 안이어도 작업 관리자 총량은
    // 상한을 넘었습니다 - 실측으로 31.8GB 기계에서 상한 8.27GB 인데 프로세스가 8.77GB 였습니다.
    //
    // 캐시가 아닌 몫을 재서 빼면 총량이 상한 안에 들어옵니다. 되먹임이라 스스로 맞습니다 -
    // 그 몫이 늘면 캐시가 줄고, 캐시가 줄면 private 이 줄어 다음 계산이 안정됩니다.
    const double overhead = static_cast<double>(non_cache_overhead_bytes()) / megabyte;
    const double floor_megabytes =
        conservative_cleaned_raw_megabytes + conservative_developed_megabytes;
    return std::max(floor_megabytes, share - overhead);
}

}  // namespace

double FrameCacheBudget::automatic_memory_fraction(
    const std::uint64_t physical_memory_bytes) noexcept {
    const double gigabytes =
        static_cast<double>(physical_memory_bytes) / (1024.0 * 1024.0 * 1024.0);
    const double steps =
        (gigabytes - automatic_fraction_reference_gigabytes) /
        automatic_fraction_step_gigabytes;
    return std::min(
        automatic_maximum_fraction,
        std::max(
            automatic_minimum_fraction,
            automatic_minimum_fraction + (steps * automatic_fraction_step)));
}

std::uint64_t FrameCacheBudget::physical_memory_bytes() noexcept {
    MEMORYSTATUSEX status{};
    status.dwLength = sizeof(status);
    if (GlobalMemoryStatusEx(&status) == 0) {
        return 0ULL;
    }
    return status.ullTotalPhys;
}

FrameCachePressureLevel current_frame_cache_pressure() noexcept {
    // 프로세스 수명 동안 하나만 씁니다. 핸들은 프로세스 종료 때 OS가 회수하며, 정적 소멸
    // 순서에서 CloseHandle을 호출해 다른 캐시 정리와 경합하지 않습니다.
    static const HANDLE low_memory =
        ::CreateMemoryResourceNotification(LowMemoryResourceNotification);
    if (low_memory == nullptr) {
        return FrameCachePressureLevel::normal;
    }
    BOOL low = FALSE;
    if (::QueryMemoryResourceNotification(low_memory, &low) == 0) {
        return FrameCachePressureLevel::normal;
    }
    return low != FALSE
        ? FrameCachePressureLevel::critical
        : FrameCachePressureLevel::normal;
}

std::uint64_t decoded_source_budget_bytes() noexcept {
    // 설정에서 고른 한도가 있으면 그것을 씁니다. macOS 와 같은 셈 —
    // cleaned raw 프레임 수 × 프레임당 190MB.
    const std::uint32_t frames =
        g_manual_cleaned_raw_frames.load(std::memory_order_relaxed);
    const double megabytes = frames > 0U
        ? static_cast<double>(frames) *
              FrameCacheBudget::cleaned_raw_megabytes_per_frame
        : automatic_budget_megabytes() * cleaned_raw_share;
    return effective_cache_budget_bytes(
        bytes_from_megabytes(megabytes), current_frame_cache_pressure());
}

std::uint64_t developed_display_budget_bytes() noexcept {
    // developed 몫을 native Rgba32F 프록시와 managed BGRA8 표시본이 화소 바이트 비율
    // 16 : 4 로 나눕니다. 여기는 그 **managed 쪽**입니다.
    const std::uint32_t frames =
        g_manual_developed_frames.load(std::memory_order_relaxed);
    const double developed_megabytes = frames > 0U
        ? static_cast<double>(frames) * FrameCacheBudget::developed_megabytes_per_frame
        : automatic_budget_megabytes() * (1.0 - cleaned_raw_share);
    return effective_cache_budget_bytes(
        bytes_from_megabytes(developed_megabytes * (1.0 - native_preview_proxy_share)),
        current_frame_cache_pressure());
}

std::uint64_t preview_proxy_budget_bytes() noexcept {
    // developed 몫은 native Rgba32F 프록시와 managed BGRA8 표시본이 나눠 씁니다 —
    // 화소 바이트 비율 16 : 4 로 가릅니다(위 `native_preview_proxy_share`).
    const std::uint32_t frames =
        g_manual_developed_frames.load(std::memory_order_relaxed);
    const double developed_megabytes = frames > 0U
        ? static_cast<double>(frames) * FrameCacheBudget::developed_megabytes_per_frame
        : automatic_budget_megabytes() * (1.0 - cleaned_raw_share);
    return effective_cache_budget_bytes(
        bytes_from_megabytes(developed_megabytes * native_preview_proxy_share),
        current_frame_cache_pressure());
}

void report_cache_resident_bytes(
    const FrameCacheKind kind, const std::uint64_t bytes) noexcept {
    const auto index = static_cast<std::size_t>(kind);
    if (index >= static_cast<std::size_t>(FrameCacheKind::count)) {
        return;
    }
    g_cache_resident_bytes[index].store(bytes, std::memory_order_relaxed);
}

std::uint64_t process_private_bytes() noexcept {
    PROCESS_MEMORY_COUNTERS_EX counters{};
    counters.cb = sizeof(counters);
    if (GetProcessMemoryInfo(
            GetCurrentProcess(),
            reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&counters),
            sizeof(counters)) == 0) {
        return 0ULL;
    }
    return static_cast<std::uint64_t>(counters.PrivateUsage);
}

std::uint64_t non_cache_overhead_bytes() noexcept {
    // 예산은 캐시가 한 장 오갈 때마다 물어봅니다. `GetProcessMemoryInfo` 는 시스템 호출이라
    // 그때마다 부르면 디코드 사슬에 눈에 띄는 값이 붙습니다. 값 자체도 그렇게 빨리 변하지
    // 않으므로 250ms 동안은 직전 값을 씁니다.
    using clock = std::chrono::steady_clock;
    static std::atomic<std::uint64_t> cached{0ULL};
    static std::atomic<std::int64_t> measured_at{0};

    const auto now =
        std::chrono::duration_cast<std::chrono::milliseconds>(
            clock::now().time_since_epoch())
            .count();
    const std::int64_t last = measured_at.load(std::memory_order_relaxed);
    if (last != 0 && now - last < 250) {
        return cached.load(std::memory_order_relaxed);
    }

    const std::uint64_t private_bytes = process_private_bytes();
    if (private_bytes == 0ULL) {
        return 0ULL;
    }
    std::uint64_t cached_bytes = 0ULL;
    for (std::size_t index = 0U;
         index < static_cast<std::size_t>(FrameCacheKind::count);
         ++index) {
        cached_bytes += g_cache_resident_bytes[index].load(std::memory_order_relaxed);
    }
    // **GPU 몫은 여기서 빼지 않습니다.**
    //
    // 외장 그래픽의 텍스처는 VRAM 에 있어 애초에 private 바이트에 없습니다 - 뺄 것이
    // 없습니다. 반대로 스테이징 두 장은 CPU 접근이라 **언제나 시스템 RAM** 이고, 내장
    // 그래픽이면 텍스처까지 시스템 RAM 입니다. 그 몫은 상한 안에서 RAM 캐시와 **경쟁해야**
    // 합니다 - 캐시로 세어 빼 주면 상한이 그만큼 늘어나 프로세스 총량이 다시 넘습니다.
    // 실측으로 8MP 스트레스에서 스테이징이 3.2GB 였습니다.

    const std::uint64_t overhead =
        private_bytes > cached_bytes ? private_bytes - cached_bytes : 0ULL;
    cached.store(overhead, std::memory_order_relaxed);
    measured_at.store(now == 0 ? 1 : now, std::memory_order_relaxed);
    return overhead;
}

}  // namespace negaflow::pipeline::develop_export_detail

namespace negaflow::pipeline {

void set_frame_cache_residency_limits(const FrameCacheResidencyLimits limits) noexcept {
    g_manual_cleaned_raw_frames.store(
        limits.cleaned_raw_frames, std::memory_order_relaxed);
    g_manual_developed_frames.store(limits.developed_frames, std::memory_order_relaxed);
}

std::uint64_t sync_display_cache_budget(const std::uint64_t resident_bytes) noexcept {
    namespace detail = negaflow::pipeline::develop_export_detail;
    // 예산을 물어보기 **전에** 알립니다 - 안 그러면 내 몫까지 간접비로 세어 예산이 두 배로
    // 깎입니다(`decode.cpp` 와 같은 규칙).
    detail::report_cache_resident_bytes(
        detail::FrameCacheKind::developed_display, resident_bytes);
    return detail::developed_display_budget_bytes();
}

FrameCacheMemoryReport frame_cache_memory_report() noexcept {
    namespace detail = negaflow::pipeline::develop_export_detail;
    FrameCacheMemoryReport report{};
    report.process_private_bytes = detail::process_private_bytes();
    report.decoded_source_resident_bytes =
        g_cache_resident_bytes[0].load(std::memory_order_relaxed);
    report.decoded_source_budget_bytes = detail::decoded_source_budget_bytes();
    report.preview_proxy_resident_bytes =
        g_cache_resident_bytes[1].load(std::memory_order_relaxed);
    report.preview_proxy_budget_bytes = detail::preview_proxy_budget_bytes();
    report.gpu_pool_resident_bytes = negaflow::gpu::gpu_pool_resident_bytes();
    // 가속기가 실제로 쓰는 장치를 봅니다. `GpuDevice::shared()` 를 부르면 D3D11 장치가
    // 하나 더 생깁니다 - 가속기는 자기 것을 따로 만듭니다.
    report.gpu_pool_limit_bytes = negaflow::gpu::GpuCacheBudget::effective_bytes(
        negaflow::pipeline::GpuAccelerator::shared().device());
    report.developed_display_resident_bytes =
        g_cache_resident_bytes[2].load(std::memory_order_relaxed);
    report.developed_display_budget_bytes = detail::developed_display_budget_bytes();
    report.gpu_system_memory_bytes = negaflow::gpu::gpu_pool_system_memory_bytes();
    report.non_cache_overhead_bytes = detail::non_cache_overhead_bytes();
    const FrameCacheResidencyLimits engine = frame_cache_residency_limits();
    report.engine_cleaned_raw_frames = engine.cleaned_raw_frames;
    report.engine_developed_frames = engine.developed_frames;
    const std::uint64_t physical = detail::FrameCacheBudget::physical_memory_bytes();
    report.automatic_process_ceiling_bytes = static_cast<std::uint64_t>(
        static_cast<double>(physical) *
        detail::FrameCacheBudget::automatic_memory_fraction(physical));
    return report;
}

FrameCacheResidencyLimits frame_cache_residency_limits() noexcept {
    return FrameCacheResidencyLimits{
        g_manual_cleaned_raw_frames.load(std::memory_order_relaxed),
        g_manual_developed_frames.load(std::memory_order_relaxed),
    };
}

}  // namespace negaflow::pipeline
