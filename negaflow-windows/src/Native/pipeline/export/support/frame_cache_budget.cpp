#include "frame_cache_budget.h"

#include "negaflow/pipeline/frame_cache_limits.h"

#include <windows.h>

#include <algorithm>
#include <atomic>

namespace {

// 설정 창이 건 상주 한도입니다. 0 은 자동입니다. 캐시는 여러 스레드에서 들어오므로 원자로
// 둡니다 — 값 두 개뿐이라 잠금까지는 필요 없고, 조금 늦게 반영돼도 다음 축출에서 맞습니다.
// 예산 함수와 설정 함수가 서로 다른 이름공간에 있어 파일 맨 위에 둡니다.
std::atomic<std::uint32_t> g_manual_cleaned_raw_frames{0U};
std::atomic<std::uint32_t> g_manual_developed_frames{0U};

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
    return total_megabytes * FrameCacheBudget::automatic_memory_fraction(physical);
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

}  // namespace negaflow::pipeline::develop_export_detail

namespace negaflow::pipeline {

void set_frame_cache_residency_limits(const FrameCacheResidencyLimits limits) noexcept {
    g_manual_cleaned_raw_frames.store(
        limits.cleaned_raw_frames, std::memory_order_relaxed);
    g_manual_developed_frames.store(limits.developed_frames, std::memory_order_relaxed);
}

FrameCacheResidencyLimits frame_cache_residency_limits() noexcept {
    return FrameCacheResidencyLimits{
        g_manual_cleaned_raw_frames.load(std::memory_order_relaxed),
        g_manual_developed_frames.load(std::memory_order_relaxed),
    };
}

}  // namespace negaflow::pipeline
