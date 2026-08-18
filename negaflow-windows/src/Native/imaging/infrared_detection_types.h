#pragma once

#include <cstddef>
#include <cstdint>
#include <limits>
#include <vector>

namespace negaflow::imaging::infrared_detail {

// 검출 전체가 공유하는 조율값 한 표입니다. 정렬·기준선·성분·확정·묶음이 모두 같은 값을
// 봐야 하므로 파일마다 다시 적지 않고 여기 한 곳에만 둡니다.
namespace tuning {

// 광학 밀도를 로그로 낼 때 0 으로 나누지 않도록 두는 바닥값입니다.
inline constexpr float kPlaneFloor = 1.0e-5F;

// 이 이상 가려진 화소를 결함의 중심(core)으로 봅니다.
inline constexpr float kCoreCut = 0.5F;

// 확정 단계가 요구하는 최소 유의도. 이보다 낮으면 결함으로 채택하지 않습니다.
inline constexpr float kMinimumSignificance = 4.0F;

// 귀무 분포를 세울 때 필요한 최소 표본 수입니다.
inline constexpr std::size_t kMinimumNullSamples = 200U;

inline constexpr double kPi = 3.14159265358979323846;

}  // namespace tuning

// 기준선 대비 신호가 어디서부터 결함인지 판정한 결과입니다.
struct SignalStatistics final {
    float floor{0.0F};
    float sigma{0.0F};
    float threshold{std::numeric_limits<float>::max()};

    [[nodiscard]] float skirt_floor() const noexcept {
        return floor + 3.0F * sigma;
    }
};

// 라벨링이 낸 연결요소 하나. 성분·확정·묶음이 이 타입을 주고받습니다.
struct RawComponent final {
    std::vector<std::size_t> pixels{};
    std::size_t source_area{0U};
    std::uint32_t min_x{0U};
    std::uint32_t min_y{0U};
    std::uint32_t max_x{0U};
    std::uint32_t max_y{0U};
};

// 한 성분이 가시 채널의 어느 자리에 어느 세기로 대응하는지 확정한 결과입니다.
struct ConfirmedDefect final {
    std::int32_t offset_x{0};
    std::int32_t offset_y{0};
    float gain{0.0F};
    float significance{0.0F};
};

// 확정된 성분과 그것이 실제로 고칠 화소 목록입니다.
struct ConfirmedCandidate final {
    RawComponent component{};
    std::vector<std::size_t> correction_pixels{};
    ConfirmedDefect match{};
};

// 상관 탐색을 위해 블록 평균으로 줄인 평면입니다.
struct DownsampledPlane final {
    std::vector<float> pixels{};
    std::uint32_t width{0U};
    std::uint32_t height{0U};
};

// 결함 자국끼리 맞춘 정렬 결과입니다.
struct DefectAlignment final {
    std::int32_t offset_x{0};
    std::int32_t offset_y{0};
    double peak{0.0};
    double runner_up{0.0};
    bool at_search_limit{false};
};

}  // namespace negaflow::imaging::infrared_detail
