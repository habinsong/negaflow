#include "frame_cache_budget.h"

#include <windows.h>

#include <algorithm>

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

std::uint64_t decoded_source_budget_bytes() noexcept {
    return bytes_from_megabytes(automatic_budget_megabytes() * cleaned_raw_share);
}

std::uint64_t preview_proxy_budget_bytes() noexcept {
    return bytes_from_megabytes(
        automatic_budget_megabytes() * (1.0 - cleaned_raw_share));
}

}  // namespace negaflow::pipeline::develop_export_detail
