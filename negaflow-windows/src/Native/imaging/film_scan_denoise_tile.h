#pragma once

#include "film_scan_denoise_types.h"

#include "negaflow/imaging/film_scan_denoise.h"

#include <cstdint>
#include <vector>

namespace negaflow::imaging::film_scan_denoise_detail {

// 타일 자리의 화소를 감마로 들어 올려 읽습니다. 어두운 쪽 잡음을 밝은 쪽과 같은 잣대로
// 보려는 것입니다.
[[nodiscard]] std::vector<Rgb> extract_lifted_tile(
    const WorkingImage& image,
    const Tile& tile);

// core 자리를 중심으로, 이미지 밖으로 나가지 않는 만큼 주변부를 붙인 타일을 만듭니다.
[[nodiscard]] Tile make_tile(
    const WorkingImage& image,
    std::uint32_t core_x,
    std::uint32_t core_y) noexcept;

// 타일 하나를 걸러 core 자리의 결과를 `output` 에 씁니다. 주변부는 쓰지 않습니다.
void process_tile(
    const WorkingImage& image,
    const FilmScanDenoiseParameters& parameters,
    const Profile& profile,
    const Tile& tile,
    std::vector<Rgb>& output);

}  // namespace negaflow::imaging::film_scan_denoise_detail
