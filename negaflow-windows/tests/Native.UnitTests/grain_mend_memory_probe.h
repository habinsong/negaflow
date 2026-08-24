#pragma once

#include <filesystem>
#include <string_view>

namespace negaflow::test_probes {

/// GrainMend 다섯 기능과 사진 A↔B 전환의 메모리 곡선을 재는 계측기입니다.
///
/// `preview_raw_store_tests.cpp` 가 500줄 규칙에 걸려 여기로 분리했습니다. 계측 대상은
/// recipe 종류마다 다른 native 경로이며, 한 기능만 재고 "누수 없음" 이라고 적지 않기
/// 위해 다섯 가지를 모두 돕니다.
///
/// `feature` 는 `auto` · `guided` · `brush` · `clone` · `infrared` · `switch` 중 하나입니다.
/// `auto` 와 `guided` 는 recipe 로는 둘 다 region 이지만, 검출이 만드는 마스크 크기가
/// 달라 상주 바이트가 다릅니다 — 그래서 따로 돕니다.
///
/// `switch` 는 `source` 와 `second_source` 를 번갈아 렌더해 사진 전환 뒤 이전 사진의
/// proxy·decoded 상주가 예산 안으로 돌아오는지 봅니다.
///
/// 성공하면 0, 인자가 잘못되면 2, 메모리 조회 실패는 3, 렌더 실패는 4를 돌려줍니다.
[[nodiscard]] int run_grain_mend_memory_probe(
    const std::filesystem::path& source,
    const std::filesystem::path& second_source,
    std::string_view feature,
    int iterations);

}  // namespace negaflow::test_probes
