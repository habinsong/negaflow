#pragma once

#include <cstdint>

namespace negaflow::pipeline::develop_export_detail {

enum class FrameCachePressureLevel : std::uint8_t {
    normal = 0,
    critical,
};

// macOS `Services/Cache/FrameCacheBudget.swift` · `FrameCachePolicy.swift` 이식본입니다.
//
// macOS 주석 원문(FrameCacheBudget.swift:5-7):
// 한도는 "미리 잡아 두는 양"이 아니라 **상한**이다. 실제로 방문한 프레임만 버퍼를 갖고,
// 한도를 넘으면 오래된 것부터 내려놓는다.
//
// 프레임 **개수**가 아니라 **바이트**로 잽니다. macOS 의 `cleanedRawMegabytesPerFrame`
// 190.0 은 "6000×4000 16bit RGBA ≈ 183MB" 라는 macOS **자기 버퍼**의 추정치입니다
// (FrameCacheBudget.swift:9-12 주석). Windows `WorkingImage` 는 화소당
// `Rgba32F` = 16바이트라 같은 원본이 5088×3401×16 = 277MB 로 **약 2배**입니다.
// 개수 한도를 그대로 옮기면 macOS 가 의도한 예산의 두 배를 씁니다. 그래서 macOS 의
// **비율**(automaticMemoryFraction)과 **배분비**(190 : 2×170)는 그대로 쓰고,
// 한 프레임의 비용만 실제 바이트로 잽니다.
struct FrameCacheBudget final {
    // FrameCacheBudget.cleanedRawMegabytesPerFrame / developedMegabytesPerFrame
    static constexpr double cleaned_raw_megabytes_per_frame = 190.0;
    static constexpr double developed_megabytes_per_frame = 170.0;
    // FrameCacheBudget.developedPerCleanedRaw
    static constexpr int developed_per_cleaned_raw = 2;

    // FrameCacheBudget.automaticMinimumFraction / automaticMaximumFraction 및 계단값
    static constexpr double automatic_minimum_fraction = 0.25;
    static constexpr double automatic_maximum_fraction = 0.35;
    static constexpr double automatic_fraction_reference_gigabytes = 16.0;
    static constexpr double automatic_fraction_step_gigabytes = 16.0;
    static constexpr double automatic_fraction_step = 0.025;

    // FrameCacheBudget.conservativeMemoryCeilingBytes
    static constexpr std::uint64_t conservative_memory_ceiling_bytes =
        8ULL * 1024ULL * 1024ULL * 1024ULL;

    // FrameCacheBudget.automaticMemoryFraction(physicalMemoryBytes:)
    [[nodiscard]] static double automatic_memory_fraction(
        std::uint64_t physical_memory_bytes) noexcept;

    // 이 기계에 설치된 물리 메모리. 실패하면 0 을 돌려주고, 호출자는 보수 예산으로 갑니다.
    [[nodiscard]] static std::uint64_t physical_memory_bytes() noexcept;
};

// 어느 캐시가 얼마를 들고 있는지입니다. 예산 계산이 "캐시가 **아닌** 몫" 을 알아야
// 프로세스 전체를 상한 안에 둘 수 있습니다.
enum class FrameCacheKind : std::uint8_t {
    decoded_source = 0,
    preview_proxy,
    count,
};

// 캐시가 상주량이 바뀔 때마다 알립니다. 값은 절대량입니다(증감이 아닙니다).
void report_cache_resident_bytes(FrameCacheKind kind, std::uint64_t bytes) noexcept;

// 지금 이 프로세스가 커밋한 private 바이트입니다. 못 읽으면 0 입니다.
[[nodiscard]] std::uint64_t process_private_bytes() noexcept;

// 캐시가 아닌 몫입니다 - 코드·런타임·WinUI·GPU 스테이징·일회성 작업 버퍼 전부입니다.
// 실측으로 설치 앱에서 약 1GB 였고, 그만큼이 어느 예산에도 들어 있지 않아 작업 관리자
// 총량이 자동 상한을 넘었습니다.
[[nodiscard]] std::uint64_t non_cache_overhead_bytes() noexcept;

// 디코드된 원본(`WorkingImage`) 상주에 쓸 바이트 예산입니다.
// macOS 배분비에서 cleaned raw 몫 = 190 / (190 + 2×170).
[[nodiscard]] std::uint64_t decoded_source_budget_bytes() noexcept;

// 프리뷰 raw 프록시(인터랙티브 + 정착) 상주에 쓸 바이트 예산입니다.
// macOS 배분비에서 developed 몫 = 2×170 / (190 + 2×170).
// macOS 주석은 이 슬롯을 developed 안에 명시합니다 — "현상본 + 변형-전 base +
// **정착 프록시 raw** 등 파생 버퍼 합계"(FrameCacheBudget.swift:12).
[[nodiscard]] std::uint64_t preview_proxy_budget_bytes() noexcept;

// Windows의 시스템 전체 저메모리 알림입니다. 알림 객체를 만들거나 읽지 못하면 normal로
// 닫습니다. 캐시 접근 시마다 다시 읽으므로 실행 중 압력 변화를 반영합니다.
[[nodiscard]] FrameCachePressureLevel current_frame_cache_pressure() noexcept;

// critical에서는 재생성 가능한 과거 프레임 예산을 0으로 내립니다. 각 캐시는 진행 중인
// 마지막 한 장을 별도로 보호합니다.
[[nodiscard]] constexpr std::uint64_t effective_cache_budget_bytes(
    const std::uint64_t normal_budget,
    const FrameCachePressureLevel pressure) noexcept {
    return pressure == FrameCachePressureLevel::critical ? 0ULL : normal_budget;
}

} // namespace negaflow::pipeline::develop_export_detail
