#pragma once

#include <cstddef>
#include <cstdint>
#include <vector>

namespace negaflow::imaging::grain_mend_detail {

// macOS `DefectScratchResponseMap` 을 그대로 옮긴 것입니다.
//
// 스크래치 방향 적분 응답의 **프레임 전역** 저해상도 맵입니다.
//
// 연장 증거 판정(`DefectStructureLineFilter`)은 컴포넌트 끝점 바깥 수십 px 를 읽어야 하는데,
// 타일 검출 안에서는 그 구간이 halo 밖으로 나가 판정 불가가 되고 컴포넌트 자체도 타일
// 경계에서 잘립니다. 그래서 타일 검출이 이미 계산해 둔 응답을 전역 좌표에 모아 두고,
// stitch 이후 프레임 전체에서 한 번에 판정합니다(응답을 새로 계산하지 않으므로 검출 비용은
// 늘지 않습니다).
//
// 저장은 2배 다운샘플 max-pooling 입니다. 판정 대상이 "수십 px 이상 이어지는 선"이라 절반
// 해상도로 충분하고, max 를 쓰므로 1px 두께 선의 응답도 소실되지 않습니다. 메모리는 원본의
// 1/4 입니다.
class ScratchResponseMap final {
public:
    /// macOS `DefectScratchResponseMap.downsample`.
    static constexpr std::uint32_t downsample = 2U;

    /// 원본(검출 ROI) 크기로 빈 맵을 만듭니다.
    ScratchResponseMap(std::uint32_t source_width, std::uint32_t source_height);

    /// 타일 응답을 전역 맵에 병합합니다(겹치는 자리는 max).
    /// - tile: 타일 로컬 응답(tile_width x tile_height, y-down).
    /// - origin_x/origin_y: 타일 좌상단의 전역 ROI 좌표(y-down).
    void merge(
        const std::vector<float>& tile,
        std::uint32_t tile_width,
        std::uint32_t tile_height,
        std::uint32_t origin_x,
        std::uint32_t origin_y);

    /// 전역 ROI 좌표(y-down)의 응답. 범위 밖이면 거짓을 돌려줍니다(= 판정 불가).
    [[nodiscard]] bool value(
        std::uint32_t x,
        std::uint32_t y,
        float& result) const noexcept;

    [[nodiscard]] std::uint32_t width() const noexcept { return width_; }

    [[nodiscard]] std::uint32_t height() const noexcept { return height_; }

private:
    std::uint32_t width_{1U};
    std::uint32_t height_{1U};
    std::vector<float> values_{};
};

}  // namespace negaflow::imaging::grain_mend_detail
