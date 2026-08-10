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
