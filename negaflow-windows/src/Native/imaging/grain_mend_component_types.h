#pragma once

#include <cstddef>
#include <cstdint>
#include <vector>

namespace negaflow::imaging::grain_mend_detail {

// 검출 게이트가 다루는 연결요소 하나. 라벨링·게이트·기각·칠하기가 모두 이 타입을 주고받으므로
// 한 곳에 둡니다 — 파일마다 같은 구조체를 다시 쓰면 필드 하나만 달라져도 조용히 어긋납니다.
struct Component final {
    std::vector<std::size_t> pixels{};
    std::uint32_t minimum_x{0U};
    std::uint32_t maximum_x{0U};
    std::uint32_t minimum_y{0U};
    std::uint32_t maximum_y{0U};
    bool has_strong{false};
    std::size_t strong_count{0U};
};

// 그레인 필드 판정에서 쓰는 작은 컴포넌트의 중심입니다.
struct SmallComponent final {
    int center_x{0};
    int center_y{0};
    bool dust{false};
    std::size_t component_index{0U};
};

// 구조선(건물 모서리·격자) 판정에서 쓰는 선분 요약입니다.
struct StructureLine final {
    int center_x{0};
    int center_y{0};
    int minimum_x{0};
    int maximum_x{0};
    int minimum_y{0};
    int maximum_y{0};
    double angle{0.0};
    double length{0.0};
    std::size_t component_index{0U};
};

// 검출 게이트의 조율값입니다. 흩어 두면 어느 파일의 값이 실제로 쓰이는지 알 수 없게 되므로
// 한 표로 모읍니다.
namespace tuning {

inline constexpr std::size_t maximum_automatic_dust_area = 150U;
inline constexpr double maximum_automatic_dust_aspect = 4.0;
inline constexpr double minimum_automatic_scratch_aspect = 2.5;
inline constexpr double minimum_pca_scratch_length = 12.0;
inline constexpr double maximum_automatic_scratch_thickness = 12.0;
inline constexpr double dust_minimum_strong_fraction = 0.08;
inline constexpr double weak_geometry_minimum_length = 80.0;
inline constexpr double weak_geometry_maximum_thickness = 3.0;
inline constexpr double weak_geometry_minimum_aspect = 15.0;
inline constexpr std::size_t isolation_minimum_structure = 8U;
inline constexpr std::uint32_t isolation_maximum_ring_padding = 24U;
inline constexpr double isolation_maximum_ring_density = 0.10;
inline constexpr std::size_t grain_field_small_component_maximum = 12U;
inline constexpr int grain_field_radius = 48;
inline constexpr int grain_field_count = 10;
inline constexpr std::size_t grid_line_minimum_field = 8U;
inline constexpr double grid_line_minimum_length = 6.0;
inline constexpr int grid_line_radius_minimum = 48;
inline constexpr int grid_line_radius_divisor = 6;
inline constexpr int grid_line_dense_count = 5;
inline constexpr double grid_line_orientation_tolerance = 22.0;
inline constexpr int grid_line_structure_radius_divisor = 4;
inline constexpr int grid_line_parallel_field = 5;
inline constexpr int grid_line_minimum_along = 2;
inline constexpr int grid_line_minimum_perpendicular = 2;
inline constexpr double grid_line_collinear_offset = 12.0;
inline constexpr double grid_line_comparable_length_ratio = 2.5;
inline constexpr int continuation_gap = 16;
inline constexpr int continuation_minimum_span = 24;
inline constexpr int continuation_maximum_span = 80;
inline constexpr double continuation_minimum_length = 12.0;
inline constexpr double continuation_short_minimum_aspect = 4.0;
inline constexpr int continuation_step = 2;
inline constexpr int continuation_perpendicular_tolerance = 2;
inline constexpr float continuation_level_ratio = 0.5F;
inline constexpr double continuation_coverage = 0.6;
inline constexpr double strong_continuation_coverage = 0.8;
inline constexpr float continuation_minimum_body_response = 1.0e-4F;

}  // namespace tuning

// 이웃 버킷 조회용 키. 구조선과 그레인 필드가 같은 격자를 쓰므로 한 벌만 둡니다.
[[nodiscard]] std::int64_t bucket_key(int x, int y) noexcept;

}  // namespace negaflow::imaging::grain_mend_detail
