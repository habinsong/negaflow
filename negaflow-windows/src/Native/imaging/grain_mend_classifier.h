#pragma once

#include <cstddef>
#include <cstdint>
#include <vector>

namespace negaflow::imaging::grain_mend_detail {

// 물리 결함 종류. macOS `DefectClassifier.swift` 의 `DefectClass` 와 순서까지 같습니다 —
// 값이 ABI 로 나가므로 순서를 바꾸면 관리 코드의 분류가 통째로 밀립니다.
//
//  dust                필름 위 이물(어두운 blob — raw 투과광을 가림)
//  pinhole             유제 구멍(작고 둥근 밝은 점 — 빛이 그대로 통과)
//  scratch_horizontal  주축 0±30°
//  scratch_vertical    주축 90±30°
//  scratch_diagonal    그 사이
//  emulsion_damage     넓고 불규칙한 유제 손상
//  micro_speck         현상 찌꺼기·유분·미세 먼지(속 검출기가 따로 냅니다)
enum class DefectClassification : std::uint8_t {
    dust = 0U,
    pinhole = 1U,
    scratch_horizontal = 2U,
    scratch_vertical = 3U,
    scratch_diagonal = 4U,
    emulsion_damage = 5U,
    micro_speck = 6U,
};

// 검출 게이트가 채택한 컴포넌트 하나. 검출 kind(먼지/스크래치)는 구조 게이트용이고,
// classification 은 표시·복원 힌트용입니다.
struct ClassifiedComponent final {
    std::vector<std::size_t> pixels{};
    std::uint32_t minimum_x{0U};
    std::uint32_t maximum_x{0U};
    std::uint32_t minimum_y{0U};
    std::uint32_t maximum_y{0U};
    bool is_scratch{false};
    DefectClassification classification{DefectClassification::dust};
    double confidence{0.5};
};

// 분류기가 읽는 국소 통계. macOS `DefectContrastField` 의 같은 이름 배열들이며, 모두
// width×height 입니다. `bright` 는 화소별 max(r,g,b) 입니다.
struct ClassifierField final {
    std::uint32_t width{0U};
    std::uint32_t height{0U};
    const std::vector<float>* dust_magnitude{nullptr};
    const std::vector<float>* thin_magnitude{nullptr};
    const std::vector<float>* noise_scale{nullptr};
    const std::vector<float>* bright{nullptr};
    // 히스테리시스 strong(core) 화소 합집합. confidence 의 증거 비율입니다.
    const std::vector<std::uint8_t>* strong{nullptr};
    // 화소별 컴포넌트 id(-1 = 배경). 극성 계산에서 라벨된 화소를 링에서 뺍니다.
    const std::vector<std::int32_t>* labels{nullptr};
};

// 채택된 컴포넌트에 분류와 confidence 를 채웁니다.
//
// **검출 결과를 바꾸지 않습니다.** 임계·SNR 게이트는 검출기가 이미 끝냈고 여기서는 채택된
// 컴포넌트의 형태·극성·증거만 읽습니다 — macOS 도 같은 자리에서 메타데이터만 채웁니다.
//
// pinhole_maximum_area  pinhole 로 인정하는 최대 면적(화소).
// emulsion_minimum_area emulsion damage 로 볼 최소 면적(화소).
void classify_components(
    std::vector<ClassifiedComponent>& components,
    const ClassifierField& field,
    std::size_t pinhole_maximum_area,
    std::size_t emulsion_minimum_area) noexcept;

}  // namespace negaflow::imaging::grain_mend_detail
