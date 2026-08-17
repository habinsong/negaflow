#include "request/develop_request_map.h"

#include "support/abi_text.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <limits>
#include <new>
#include <string>
#include <string_view>
#include <vector>

namespace negaflow::abi::detail {

// 정수 ABI 값을 파이프라인 enum 으로 옮깁니다. 캐스트가 아니라 명시 분기로 둡니다.

[[nodiscard]] bool map_export_format(
    const std::uint32_t value,
    negaflow::pipeline::DevelopExportFormat& format) noexcept {
    switch (value) {
        case NF_EXPORT_FORMAT_PNG16:
            format = negaflow::pipeline::DevelopExportFormat::png16;
            return true;
        case NF_EXPORT_FORMAT_TIFF16:
            format = negaflow::pipeline::DevelopExportFormat::tiff16;
            return true;
        case NF_EXPORT_FORMAT_JPEG8:
            format = negaflow::pipeline::DevelopExportFormat::jpeg8;
            return true;
        default:
            return false;
    }
}

[[nodiscard]] bool map_film_type(
    const std::uint32_t value,
    negaflow::imaging::NegativeFilmType& film_type) noexcept {
    switch (value) {
        case NF_FILM_TYPE_COLOR:
            film_type = negaflow::imaging::NegativeFilmType::color;
            return true;
        case NF_FILM_TYPE_BLACK_AND_WHITE:
            film_type = negaflow::imaging::NegativeFilmType::black_and_white;
            return true;
        default:
            return false;
    }
}

[[nodiscard]] bool map_source_kind(
    const std::uint32_t value,
    negaflow::imaging::DevelopSourceKind& source_kind) noexcept {
    switch (value) {
        case NF_DEVELOP_SOURCE_FILM_SCAN:
            source_kind = negaflow::imaging::DevelopSourceKind::film_scan;
            return true;
        case NF_DEVELOP_SOURCE_RENDERED_DIGITAL:
            source_kind = negaflow::imaging::DevelopSourceKind::rendered_digital;
            return true;
        default:
            return false;
    }
}

[[nodiscard]] bool map_film_polarity(
    const std::uint32_t value,
    negaflow::pipeline::FilmPolarity& polarity) noexcept {
    switch (value) {
        case NF_FILM_POLARITY_NEGATIVE:
            polarity = negaflow::pipeline::FilmPolarity::negative;
            return true;
        case NF_FILM_POLARITY_POSITIVE:
            polarity = negaflow::pipeline::FilmPolarity::positive;
            return true;
        default:
            return false;
    }
}

[[nodiscard]] bool map_base_estimation_mode(
    const std::uint32_t value,
    negaflow::pipeline::NegativeBaseEstimationMode& mode) noexcept {
    switch (value) {
        case NF_BASE_ESTIMATION_AUTO:
            mode = negaflow::pipeline::NegativeBaseEstimationMode::auto_estimate;
            return true;
        case NF_BASE_ESTIMATION_PRESET:
            mode = negaflow::pipeline::NegativeBaseEstimationMode::preset;
            return true;
        case NF_BASE_ESTIMATION_MANUAL:
            mode = negaflow::pipeline::NegativeBaseEstimationMode::manual;
            return true;
        default:
            return false;
    }
}

// Explicit rather than a cast, so adding a profile on either side cannot silently
// shift what an existing catalog value means.
[[nodiscard]] bool map_film_emulation(
    const std::uint32_t value,
    negaflow::imaging::FilmEmulation& emulation) noexcept {
    using negaflow::imaging::FilmEmulation;
    switch (value) {
        case 0U: emulation = FilmEmulation::none; return true;
        case 1U: emulation = FilmEmulation::ektachrome_e100; return true;
        case 2U: emulation = FilmEmulation::provia_100f; return true;
        case 3U: emulation = FilmEmulation::velvia_50; return true;
        case 4U: emulation = FilmEmulation::portra_160; return true;
        case 5U: emulation = FilmEmulation::portra_400; return true;
        case 6U: emulation = FilmEmulation::portra_800; return true;
        case 7U: emulation = FilmEmulation::ektar_100; return true;
        case 8U: emulation = FilmEmulation::ultramax_400; return true;
        case 9U: emulation = FilmEmulation::colorplus_200; return true;
        case 10U: emulation = FilmEmulation::fujicolor_c200; return true;
        case 11U: emulation = FilmEmulation::pro_400h; return true;
        case 12U: emulation = FilmEmulation::tri_x_400; return true;
        case 13U: emulation = FilmEmulation::hp5_plus; return true;
        case 14U: emulation = FilmEmulation::fp4_plus; return true;
        case 15U: emulation = FilmEmulation::delta_100; return true;
        case 16U: emulation = FilmEmulation::delta_400; return true;
        case 17U: emulation = FilmEmulation::delta_3200; return true;
        case 18U: emulation = FilmEmulation::tmax_100; return true;
        case 19U: emulation = FilmEmulation::tmax_400; return true;
        case 20U: emulation = FilmEmulation::tmax_p3200; return true;
        case 21U: emulation = FilmEmulation::kentmere_400; return true;
        case 22U: emulation = FilmEmulation::ortho_plus; return true;
        case 23U: emulation = FilmEmulation::sfx_200; return true;
        case 24U: emulation = FilmEmulation::rollei_ir; return true;
        case 25U: emulation = FilmEmulation::scala_200x; return true;
        case 26U: emulation = FilmEmulation::rollei_superpan; return true;
        case 27U: emulation = FilmEmulation::velvia_100; return true;
        case 28U: emulation = FilmEmulation::e100_vs; return true;
        case 29U: emulation = FilmEmulation::astia_100f; return true;
        case 30U: emulation = FilmEmulation::kodachrome_64; return true;
        case 31U: emulation = FilmEmulation::gold_200; return true;
        case 32U: emulation = FilmEmulation::pro_image_100; return true;
        case 33U: emulation = FilmEmulation::superia_400; return true;
        case 34U: emulation = FilmEmulation::superia_premium_400; return true;
        case 35U: emulation = FilmEmulation::superia_200; return true;
        case 36U: emulation = FilmEmulation::reala_100; return true;
        case 37U: emulation = FilmEmulation::industrial_100; return true;
        case 38U: emulation = FilmEmulation::lomo_cn_800; return true;
        case 39U: emulation = FilmEmulation::vision3_500t; return true;
        case 40U: emulation = FilmEmulation::vision3_250d; return true;
        case 41U: emulation = FilmEmulation::vision3_50d; return true;
        case 42U: emulation = FilmEmulation::vision3_200t; return true;
        default: return false;
    }
}

}  // namespace negaflow::abi::detail
