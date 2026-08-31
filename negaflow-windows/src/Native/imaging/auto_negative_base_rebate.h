#pragma once

// 자동 베이스가 **틀렸을 때만** 도는 구조길입니다.
//
// 지금 추정기는 5136 폭을 256 폭으로 줄인 격자에서 베이스를 찾습니다. 리베이트(사진이
// 찍히지 않은 필름 여백)가 얇으면 그 축소에서 주변 화소와 평균되어 사라지고, 다음으로
// 밝은 덩어리인 **사진 내용**이 베이스로 뽑힙니다. 그러면 반전의 0 점이 낮게 앉아 사진이
// 통째로 어두워집니다(OpticFilm8100-0001, 자동 0.143/0.060/0.029, 실제 0.357/0.149/0.075).
//
// 여기서는 그것을 **되돌리지 않습니다.** 기존 경로가 낸 값을 그대로 두고, 그 값이 물리적
// 으로 말이 되는지만 보고, 안 되면 그때만 원본 해상도에서 다시 잽니다. 정상 사진은
// 문지기에서 걸러져 한 화소도 더 읽지 않습니다.

#include "film_base_sampling.h"

#include "negaflow/imaging/manual_negative_developer.h"

#include <array>
#include <cstddef>
#include <cstdint>
#include <optional>

namespace negaflow::imaging::auto_base_detail {

/// <summary>고른 베이스보다 밝은 필름 화소의 비율입니다.</summary>
///
/// 필름에서 베이스보다 밝은 것은 없습니다 — 베이스는 아무것도 안 찍힌 자리라 빛을 가장
/// 많이 통과시킵니다. 그러니 "베이스보다 밝은 화소가 잔뜩 있다" 는 것은 사진이 어두운지
/// 밝은지와 무관하게 **그 자체로 모순**이며, 고른 값이 베이스가 아니라는 뜻입니다.
///
/// 이 판정이 밝기가 아니라 모순을 보기 때문에 야경도 안전합니다. 야경은 네거티브에서
/// 오히려 베이스 쪽으로 붙으므로(빛을 적게 받아 얇습니다) 베이스보다 밝은 화소가 생기지
/// 않습니다. 필름 종류·스캐너 노출·화이트밸런스와도 무관합니다.
[[nodiscard]] double brighter_than_base_fraction(
    const film_base_detail::SampleGrid& grid,
    const std::array<float, 3>& dmin) noexcept;

/// <summary>리베이트 띠에서 다시 잰 베이스입니다. 띠가 없으면 <c>nullopt</c> 입니다.</summary>
///
/// 두 단계입니다. **찾기** 는 축소본에서 하고 — 띠의 자리만 알면 되므로 축소본으로
/// 충분합니다 — **재기** 는 찾은 자리에서 원본 해상도로 합니다. 축소본에서 읽은 값은
/// 주변과 평균되어 실제보다 낮기 때문입니다(격자 0.16, 원본 0.19).
///
/// 찾기 기준은 백분위가 아니라 **길이** 입니다: 어떤 줄에서 후보 화소가 줄 길이의 일정
/// 비율만큼 연속으로 이어지면서 모두 luma ≥ L 이면 그 줄은 수준 L 을 유지합니다. 먼지와
/// 흠집은 짧아서 못 버티고 리베이트는 폭 전체를 가로지르므로 버팁니다. 길이로 정의하면
/// 띠가 16 줄이든 400 줄이든 결과가 같습니다 — 고정 백분위가 깨지던 자리입니다.
/// <param name="gate_open">
/// 문지기가 열렸습니다 — 고른 값이 장면 높이에 앉아 있다는 뜻입니다.
/// </param>
///
/// 문지기가 닫혀 있어도 **띠가 얇으면** 원본을 봅니다. 축소본에서 얇은 띠는 이웃과 평균되어
/// 절반 값으로 뭉개지고, 추정기가 그 뭉개진 값을 고르면 사진이 어두워지는데 — 그 값은 장면
/// 보다는 밝아서 문지기에 안 걸립니다. 얇은 띠는 그 자체로 "여기서 읽은 값은 못 믿는다" 는
/// 표시이므로, 그때만 원본에서 확인합니다.
[[nodiscard]] std::optional<film_base_detail::BaseMeasurement> rebate_base(
    const WorkingImage& image,
    const film_base_detail::SampleGrid& grid,
    NegativeFilmType film_type,
    bool gate_open);

/// <summary>다시 잰 값을 받아들일지입니다.</summary>
///
/// 문지기는 넉넉하게 의심하므로(멀쩡한 사진도 걸립니다) 채택은 여기서 깐깐하게 봅니다.
/// 받아들이지 않으면 기존 값이 그대로 남습니다 — 새 경로가 아무 답도 못 내는 사진은
/// 구조적으로 지금과 똑같이 동작합니다.
///
/// 다시 잰 값이 지금 값보다 **뚜렷하게** 밝아야 받습니다. 띠 찾기를 늘 돌리게 되면서
/// 멀쩡한 사진에서도 같은 자리를 다시 재게 되는데, 그때 나오는 값은 지금 값과 사실상
/// 같습니다. 여유 없이 "밝기만 하면" 으로 두면 그 미세한 차이로 멀쩡한 사진이 바뀝니다.
[[nodiscard]] bool accept_rebate_base(
    const film_base_detail::BaseMeasurement& rebate,
    const std::array<float, 3>& current) noexcept;

}  // namespace negaflow::imaging::auto_base_detail
