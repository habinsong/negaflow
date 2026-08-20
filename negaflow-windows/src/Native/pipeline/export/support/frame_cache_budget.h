#pragma once

#include <cstdint>

namespace negaflow::pipeline::develop_export_detail {

// macOS `Services/Cache/FrameCacheBudget.swift` · `FrameCachePolicy.swift` 이식본입니다.
//
// macOS 주석 원문(FrameCacheBudget.swift:5-7):
//   한도는 "미리 잡아 두는 양"이 아니라 **상한**이다. 실제로 방문한 프레임만 버퍼를 갖고,
//   한도를 넘으면 오래된 것부터 내려놓는다.
//
// ☠️ 프레임 **개수**가 아니라 **바이트**로 잽니다. macOS 의 `cleanedRawMegabytesPerFrame`
//    190.0 은 "6000×4000 16bit RGBA ≈ 183MB" 라는 macOS **자기 버퍼**의 추정치입니다
//    (FrameCacheBudget.swift:9-12 주석). Windows `WorkingImage` 는 화소당
//    `Rgba32F` = 16바이트라 같은 원본이 5088×3401×16 = 277MB 로 **약 2배**입니다.
//    개수 한도를 그대로 옮기면 macOS 가 의도한 예산의 두 배를 씁니다. 그래서 macOS 의
//    **비율**(automaticMemoryFraction)과 **배분비**(190 : 2×170)는 그대로 쓰고,
//    한 프레임의 비용만 실제 바이트로 잽니다.
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

// 디코드된 원본(`WorkingImage`) 상주에 쓸 바이트 예산입니다.
// macOS 배분비에서 cleaned raw 몫 = 190 / (190 + 2×170).
[[nodiscard]] std::uint64_t decoded_source_budget_bytes() noexcept;

// 프리뷰 raw 프록시(인터랙티브 + 정착) 상주에 쓸 바이트 예산입니다.
// macOS 배분비에서 developed 몫 = 2×170 / (190 + 2×170).
// macOS 주석은 이 슬롯을 developed 안에 명시합니다 — "현상본 + 변형-전 base +
// **정착 프록시 raw** 등 파생 버퍼 합계"(FrameCacheBudget.swift:12).
[[nodiscard]] std::uint64_t preview_proxy_budget_bytes() noexcept;

}  // namespace negaflow::pipeline::develop_export_detail
