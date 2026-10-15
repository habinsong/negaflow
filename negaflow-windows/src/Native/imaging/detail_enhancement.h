#pragma once

#include "texture_stage_math.h"

#include <cstddef>

namespace negaflow::imaging::texture_stage_detail {

// 선명도·부분 대비입니다(macOS `DetailEnhancement`). 둘 다 감마(sRGB 인코딩) 휘도에서 디테일을
// 다루고 휘도 비율로 RGB 에 실어 색상·채도를 건드리지 않습니다. 공간 척도는 작업 영상의 긴 변에
// 비례합니다(기준 6000px) — 화면 프록시와 내보내기 원본이 같은 사진에 같은 상대 크기로 겁니다.

// 선명도: 감마 휘도 언샤프. 문턱 아래 미세 진폭(노이즈·그레인 바닥)은 키우지 않고, 증폭분은
// 부드럽게 묶어 큰 경계의 헤일로를 막습니다. `sharpness` 는 0…1 입니다.
void apply_detail_sharpen(
    WorkingImage& image,
    float sharpness,
    std::size_t& scratch_peak_bytes);

// 부분 대비: 경계 보존 베이스(축소 해상도 자기 안내 가이디드 필터)에 대한 디테일을 키우거나(+)
// 줄입니다(−). `clarity` 는 −1…1 입니다.
void apply_local_contrast(WorkingImage& image, float clarity);

}  // namespace negaflow::imaging::texture_stage_detail
