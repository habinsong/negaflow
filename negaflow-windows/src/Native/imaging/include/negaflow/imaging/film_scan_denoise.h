#pragma once

#include "negaflow/core/cancel_flag.h"
#include "negaflow/core/pixel.h"
#include "negaflow/imaging/scanner_to_working.h"

#include <cstddef>
#include <cstdint>

namespace negaflow::imaging {

inline constexpr char film_scan_denoise_algorithm_version[] =
    "chromabase-film-scan-denoise-cpu-v1";
inline constexpr float film_scan_denoise_identity_threshold = 1.0e-3F;
inline constexpr std::uint32_t film_scan_denoise_tile_side = 512U;
// The macOS Gaussian has unbounded mathematical support. The CPU baseline fixes
// a +/-3 sigma truncation for radius 1.3, then adds both radius-7 guided-filter
// box passes: ceil(3*1.3) + 7 + 7 = 18 pixels.
inline constexpr std::uint32_t film_scan_denoise_tile_apron = 18U;

enum class FilmScanDenoiseFilmProfile : std::uint8_t {
    color_negative = 0,
    color_positive,
    black_and_white_negative,
    black_and_white_positive,
};

struct FilmScanDenoiseAxes final {
    float luma{0.5F};
    float chroma{0.5F};
    float dark_tone{0.5F};
    float detail{0.5F};
    float grain_protect{0.0F};
};

struct FilmScanDenoiseParameters final {
    float strength{0.0F};
    FilmScanDenoiseFilmProfile film_profile{
        FilmScanDenoiseFilmProfile::color_negative};
    FilmScanDenoiseAxes axes{};
};

enum class FilmScanDenoiseStatus : std::uint8_t {
    ok = 0,
    invalid_parameter,
    cancelled,
    kernel_failed,
    allocation_failed,
};

struct FilmScanDenoiseInfo final {
    bool applied{false};
    std::uint32_t tiles_processed{0U};
    std::size_t output_scratch_bytes{0U};
    negaflow::core::KernelStatus kernel_status{
        negaflow::core::KernelStatus::ok};
};

struct FilmScanDenoiseResult final {
    FilmScanDenoiseStatus status{FilmScanDenoiseStatus::invalid_parameter};
    FilmScanDenoiseInfo info{};
    WorkingImage image{};
};

// ── 그래프 상수와 필름별 세기 ────────────────────────────────────────────────
//
// 원래 이 여섯은 `film_scan_denoise_types.h`(private)와 `film_scan_denoise.cpp` 의 익명
// 이름공간에 있었습니다. **GPU 이식이 같은 값을 필요로 하면서 공개로 올렸습니다** —
// 두 벌을 두면 한쪽만 고쳐도 조용히 갈립니다. CPU 쪽은 그대로 이 정의를 씁니다.

// 어두운 쪽 잡음을 균등하게 보려고 이 지수로 들어 올린 뒤 거릅니다.
inline constexpr float film_scan_denoise_gamma_lift_power = 0.45F;
inline constexpr float film_scan_denoise_inverse_gamma_lift_power =
    1.0F / film_scan_denoise_gamma_lift_power;
// 유도 필터의 정칙화 항입니다. 작을수록 경계를 더 살립니다.
inline constexpr float film_scan_denoise_guided_epsilon = 0.001F;
inline constexpr float film_scan_denoise_gaussian_radius = 1.3F;
// `film_scan_denoise_tile.cpp:79,81` 이 쓰는 두 반경입니다.
inline constexpr int film_scan_denoise_guided_radius_middle = 3;
inline constexpr int film_scan_denoise_guided_radius_coarse = 7;

// 필름 종류가 정하는 세기입니다. 컬러 네거티브와 흑백은 잡음의 성질이 달라 같은 세기를
// 쓸 수 없습니다.
struct FilmScanDenoiseFilmScalars final {
    float luma_scale;
    float chroma_scale;
    float shadow_boost;
    float highlight_chroma;
    float highlight_luma_protect;
    bool monochrome;
};

[[nodiscard]] constexpr FilmScanDenoiseFilmScalars film_scan_denoise_film_scalars(
    const FilmScanDenoiseFilmProfile profile) noexcept {
    switch (profile) {
        case FilmScanDenoiseFilmProfile::color_negative:
            return {1.0F, 1.0F, 0.6F, 0.8F, 0.45F, false};
        case FilmScanDenoiseFilmProfile::color_positive:
            return {1.0F, 0.9F, 1.1F, 0.25F, 0.65F, false};
        case FilmScanDenoiseFilmProfile::black_and_white_negative:
            return {1.15F, 0.0F, 0.7F, 0.0F, 0.45F, true};
        case FilmScanDenoiseFilmProfile::black_and_white_positive:
            return {1.15F, 0.0F, 1.1F, 0.0F, 0.65F, true};
    }
    return {};
}

[[nodiscard]] bool valid_film_scan_denoise_parameters(
    const FilmScanDenoiseParameters& parameters) noexcept;

// CPU oracle for the fixed macOS FilmScanDenoise graph. The image is processed
// in overlap tiles with the fixed 18px apron; preview and export call this same
// function. Alpha is preserved. Any failure discards pixels so a partial tile
// result cannot be published.
// Tiles read an apron but write only their own core, so the tile rows run concurrently
// and the result is unchanged. Cancellation is checked per tile row.
[[nodiscard]] FilmScanDenoiseResult apply_film_scan_denoise(
    WorkingImage image,
    const FilmScanDenoiseParameters& parameters,
    negaflow::core::CancelFlag cancel = {}) noexcept;

[[nodiscard]] const char* film_scan_denoise_status_name(
    FilmScanDenoiseStatus status) noexcept;

}  // namespace negaflow::imaging
