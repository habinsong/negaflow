#pragma once

#include "flatbed_frame_grid_types.h"

#include "negaflow/imaging/flatbed_frame_grid_detector.h"

#include <vector>

namespace negaflow::imaging::flatbed_detail {

// 홀더의 스트립 자리를 찾습니다. 열 프로파일이 두 무리로 갈리지 않으면 빈 목록입니다.
[[nodiscard]] std::vector<Slot> slots(
    const FlatbedFramePreview& preview,
    const ColumnProfiles& profiles,
    const Geometry& geometry);

// 스트립 바깥 유리면의 대비로 잰 잡음 바닥입니다. 빈 프레임과 어두운 프레임을 가릅니다.
[[nodiscard]] double noise_floor(
    const ColumnProfiles& profiles,
    const std::vector<Slot>& slots);

// 띠의 위아래 끝을 필름이 실제로 있는 자리까지 좁힙니다.
[[nodiscard]] IntRange trim_band(
    IntRange band,
    const RowProfiles& rows,
    const Geometry& geometry);

// 한 스트립 안에서 필름이 이어진 세로 구간들입니다.
[[nodiscard]] std::vector<IntRange> film_bands(
    const FlatbedFramePreview& preview,
    const RowProfiles& rows,
    const Geometry& geometry);

// 프레임 사이 간격이 어디에 있는지의 증거입니다. 격자 맞추기가 이것만 봅니다.
[[nodiscard]] GapEvidence gap_evidence(
    const RowProfiles& rows,
    IntRange band,
    const Geometry& geometry);

// 이 피치에서 간격의 반너비입니다. 포맷이 정한 최소·최대 안으로 자릅니다.
[[nodiscard]] double gap_half_width(double pitch, const Geometry& geometry) noexcept;

}  // namespace negaflow::imaging::flatbed_detail
