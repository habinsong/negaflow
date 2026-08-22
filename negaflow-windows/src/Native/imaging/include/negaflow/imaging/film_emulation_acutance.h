#pragma once

#include "negaflow/core/pixel.h"
#include "negaflow/imaging/film_emulation_color.h"

#include <cstddef>
#include <cstdint>

namespace negaflow::imaging {

inline constexpr char film_emulation_acutance_algorithm_version[] =
    "chromabase-film-emulation-acutance-v1";
inline constexpr std::uint32_t film_emulation_acutance_support = 5U;
inline constexpr std::uint32_t film_emulation_acutance_scratch_rows =
    (film_emulation_acutance_support * 2U) + 1U;

struct FilmEmulationAcutanceParameters final {
    FilmEmulation emulation{FilmEmulation::none};
    double intensity{0.5};
};

struct FilmEmulationAcutanceProfile final {
    double radius;
    double intensity;
};

struct FilmEmulationAcutanceScratchPixel final {
    float red;
    float green;
    float blue;
};

static_assert(sizeof(FilmEmulationAcutanceScratchPixel) == 12U);

struct FilmEmulationAcutanceScratch final {
    FilmEmulationAcutanceScratchPixel* pixels;
    std::size_t pixel_capacity;
};

// 화소 루프 **밖에서** 한 번 정해지는 것들입니다. 분리형 11탭 가우시안의 가중치와
// 언샤프 세기.
//
// **GPU 판이 이것을 그대로 씁니다.** 가중치를 두 곳에서 만들면 그 순간 두 벌이 되고,
// `exp` 구현 차이가 화소마다 실립니다. `prepare_color_grading` 과 같은 이유로
// 준비 계산을 한 곳에만 둡니다.
struct FilmEmulationAcutanceSetup final {
    float weights[film_emulation_acutance_scratch_rows]{};
    float amount{0.0F};
    // 거짓이면 CPU 는 커널을 안 돌리고 **원본을 복사**합니다. GPU 도 같아야 합니다.
    bool applied{false};
};

[[nodiscard]] FilmEmulationAcutanceSetup prepare_film_emulation_acutance(
    const FilmEmulationAcutanceParameters& parameters) noexcept;

[[nodiscard]] bool valid_film_emulation_acutance_parameters(
    const FilmEmulationAcutanceParameters& parameters) noexcept;
[[nodiscard]] bool has_film_emulation_acutance_change(
    const FilmEmulationAcutanceParameters& parameters) noexcept;
[[nodiscard]] double film_emulation_acutance_amount(
    const FilmEmulationAcutanceParameters& parameters) noexcept;
[[nodiscard]] bool try_get_film_emulation_acutance_profile(
    FilmEmulation emulation,
    FilmEmulationAcutanceProfile& profile) noexcept;

// The active separable filter needs only eleven horizontally blurred RGB rows.
// It never allocates or retains another full-frame image.
[[nodiscard]] std::size_t film_emulation_acutance_scratch_pixel_count(
    std::uint32_t width) noexcept;

// Input/output is extended-linear sRGB. RGB may overshoot the unit interval;
// alpha is copied unchanged. Exact in-place operation is supported when both
// views have the same base pointer and stride. Scratch must not overlap either
// image view.
[[nodiscard]] negaflow::core::KernelStatus apply_film_emulation_acutance(
    negaflow::core::ConstImageView input,
    negaflow::core::ImageView output,
    const FilmEmulationAcutanceParameters& parameters,
    FilmEmulationAcutanceScratch scratch) noexcept;

} // namespace negaflow::imaging
