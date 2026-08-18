#pragma once

#include "negaflow/core/pixel.h"
#include "negaflow/imaging/digital_bw_film_look.h"
#include "negaflow/imaging/digital_film_color_preset.h"
#include "negaflow/imaging/digital_film_grain.h"
#include "negaflow/imaging/digital_halation.h"
#include "negaflow/imaging/film_emulation_acutance.h"
#include "negaflow/imaging/film_emulation_color.h"
#include "negaflow/imaging/scanner_to_working.h"

#include <cstddef>
#include <cstdint>

namespace negaflow::imaging {

inline constexpr char working_film_look_algorithm_version[] =
    "chromabase-working-film-look-v4";

enum class DevelopSourceKind : std::uint8_t {
    film_scan = 0,
    rendered_digital,
};

enum class FilmLookRoute : std::uint8_t {
    invalid = 0,
    identity,
    film_scan_emulation,
    digital_film_look,
};

enum class WorkingFilmLookStatus : std::uint8_t {
    ok = 0,
    invalid_parameter,
    unsupported_route,
    kernel_failed,
    digital_halation_failed,
    digital_color_preset_failed,
    digital_grain_failed,
    digital_bw_film_look_failed,
};

struct WorkingFilmLookParameters final {
    DevelopSourceKind source_kind{DevelopSourceKind::film_scan};
    FilmEmulation emulation{FilmEmulation::none};
    double intensity{0.5};
    double grain_override{0.0};
    double halation_override{0.0};
    bool monochrome{false};
};

// The caller retains both reusable resources. The color cube is built only
// when its profile/quantized intensity does not match. Acutance scratch is
// width-bounded and may be empty for an identity route.
struct WorkingFilmLookWorkspace final {
    FilmEmulationColorCube* color_cube{nullptr};
    FilmEmulationAcutanceScratch acutance{};
};

struct WorkingFilmLookInfo final {
    FilmLookRoute route{FilmLookRoute::invalid};
    bool color_cube_built{false};
    bool color_cube_reused{false};
    bool color_applied{false};
    bool acutance_applied{false};
    bool digital_halation_applied{false};
    bool digital_color_preset_applied{false};
    bool digital_grain_applied{false};
    bool bw_emulsion_applied{false};
    std::uint32_t color_intensity_step{0U};
    double acutance_amount{0.0};
    std::size_t required_acutance_scratch_pixels{0U};
    negaflow::core::KernelStatus kernel_status{
        negaflow::core::KernelStatus::ok};
};

struct WorkingFilmLookResult final {
    WorkingFilmLookStatus status{WorkingFilmLookStatus::invalid_parameter};
    WorkingFilmLookInfo info{};
    WorkingImage image{};
};

// 디지털 원본 사슬을 GPU 오케스트레이터에 넘길 때 쓰는 계획입니다.
//
// 왜 계획을 CPU 가 만드나 — 재료마다 "돌릴지 말지" 를 정하는 게이트가 있고, 그 판정을
// GPU 쪽에서 다시 하면 **두 벌이 되어 갈라집니다.** 여기서는 CPU 가 한 번 판정해
// 넘기고, GPU 는 **순서대로 돌리기만** 합니다. 비어 있는 칸(널 포인터·`applied=false`·
// 세기 0)은 건너뜁니다 — 그것이 CPU 의 조기 반환과 같은 자리입니다.
//
// 왜 오케스트레이터가 따로 필요한가 — 재료마다 올렸다 내리면 24MP 에서 왕복이 다섯 번,
// 277 MB × 10 입니다. 실측으로 그 전송이 커널보다 훨씬 컸습니다.
struct DigitalFilmLookPlan final {
    DigitalHalationMaterial halation_material{};
    double halation_strength{0.0};
    bool halation_requested{false};
    // 널이면 색 큐브를 건너뜁니다.
    const FilmEmulationColorCube* cube{nullptr};
    FilmEmulationAcutanceSetup acutance{};
    // 널이면 색 프리셋을 건너뜁니다.
    const DigitalFilmColorPreset* preset{nullptr};
    float preset_strength{0.0F};
    DigitalFilmGrainProfile grain{0.0, 0.0, 1.0};
    double grain_strength{0.0};
    bool grain_requested{false};
};

struct DigitalFilmLookApplied final {
    bool halation{false};
    bool color{false};
    bool acutance{false};
    bool preset{false};
    bool grain{false};
};

[[nodiscard]] bool valid_working_film_look_parameters(
    const WorkingFilmLookParameters& parameters) noexcept;

// The route is explicit and never inferred from a path, decoder, film type, or
// pixel statistics. Current macOS behavior keeps every film scan at identity to
// avoid applying emulsion response twice; rendered digital alone resolves to
// the complete DigitalFilmLook route.
[[nodiscard]] bool try_resolve_film_look_route(
    const WorkingFilmLookParameters& parameters,
    FilmLookRoute& route) noexcept;

// Applies only a complete route. Film scans preserve pixels. Rendered digital
// uses the fixed macOS color or B&W DigitalFilmLook order. A profile whose kind
// does not match the process is identity. Any failure discards pixels so a
// partial look cannot publish.
// kernel_status is meaningful when status is kernel_failed.
[[nodiscard]] WorkingFilmLookResult apply_working_film_look(
    WorkingImage image,
    const WorkingFilmLookParameters& parameters,
    WorkingFilmLookWorkspace workspace = {}) noexcept;

[[nodiscard]] const char* develop_source_kind_name(
    DevelopSourceKind source_kind) noexcept;
[[nodiscard]] const char* film_look_route_name(FilmLookRoute route) noexcept;
[[nodiscard]] const char* working_film_look_status_name(
    WorkingFilmLookStatus status) noexcept;

}  // namespace negaflow::imaging
