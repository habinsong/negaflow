#include "negaflow/abi/film_base_pick.h"

#include "negaflow/imaging/film_base_picker.h"
#include "negaflow/imaging/scanner_tiff_to_working.h"

#include <cstdint>
#include <filesystem>

// 필름 베이스 스포이드 C ABI 입니다. macOS `AppModel.pickFilmBase` 가 부르는
// `FilmBasePicker.sample` 과 같은 자리이며, 원본을 읽어 클릭 지점의 Dmin 을 냅니다.

nf_status_t NF_CALL nf_pick_film_base_v1(
    const wchar_t* const source_path,
    const double unit_x,
    const double unit_y,
    const uint32_t film_type,
    nf_film_base_pick_v1* const result) {
    if (result == nullptr ||
        result->struct_size < static_cast<std::uint32_t>(sizeof(*result))) {
        return NF_STATUS_INVALID_ARGUMENT;
    }
    result->status = NF_FILM_BASE_PICK_INVALID_IMAGE;
    result->red = 0.0F;
    result->green = 0.0F;
    result->blue = 0.0F;
    if (source_path == nullptr || film_type > 1U) {
        return NF_STATUS_INVALID_ARGUMENT;
    }

    try {
        negaflow::imageio::WicTiffDecodeControl decode_control{};
        decode_control.rows_per_copy = 64U;
        const auto prepared = negaflow::imaging::decode_scanner_tiff_to_working_rows(
            std::filesystem::path{source_path}, {}, {}, decode_control);
        if (prepared.decode.status != negaflow::imageio::WicTiffDecodeStatus::ok ||
            prepared.working.status != negaflow::imaging::ScannerToWorkingStatus::ok) {
            return NF_STATUS_OK;
        }
        const negaflow::imaging::FilmBasePickResult picked =
            negaflow::imaging::sample_film_base(
                prepared.working.image,
                unit_x,
                unit_y,
                film_type == 1U ? negaflow::imaging::NegativeFilmType::black_and_white
                                : negaflow::imaging::NegativeFilmType::color);
        switch (picked.status) {
            case negaflow::imaging::FilmBasePickStatus::ok:
                result->status = NF_FILM_BASE_PICK_OK;
                result->red = picked.rgb[0];
                result->green = picked.rgb[1];
                result->blue = picked.rgb[2];
                break;
            case negaflow::imaging::FilmBasePickStatus::implausible:
                result->status = NF_FILM_BASE_PICK_IMPLAUSIBLE;
                break;
            case negaflow::imaging::FilmBasePickStatus::invalid_image:
                result->status = NF_FILM_BASE_PICK_INVALID_IMAGE;
                break;
        }
        return NF_STATUS_OK;
    } catch (...) {
        // 할당·파일 실패가 noexcept ABI 경계를 넘게 두지 않습니다. 호출부는 Dmin 을
        // 바꾸지 않습니다.
        result->status = NF_FILM_BASE_PICK_INVALID_IMAGE;
        return NF_STATUS_OK;
    }
}
