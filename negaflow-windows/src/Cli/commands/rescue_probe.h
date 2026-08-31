#pragma once

namespace negaflow::cli {

// EXPIRED(RescueGrade)가 실제 사진에서 무엇을 보고 물러났는지 재는 자리입니다.
//
// 합성 캐스트로만 확인하면 "시험은 통과하는데 그 사진은 그대로" 가 됩니다. 자동 베이스로
// 현상한 뒤 EXPIRED 를 걸고, 통과한 밴드 수·덮은 칸 수·표본 수와 색 벌어짐의 앞뒤를 그대로
// 냅니다 — 어느 관문에서 멈췄는지 그 숫자로 갈립니다.
[[nodiscard]] int run_rescue_probe(int argument_count, const wchar_t* const arguments[]);

}  // namespace negaflow::cli
