#pragma once

namespace negaflow::cli {

// 실제 스캔 한 장에 자동 필름 베이스 추정을 한 번 걸고, 어느 단계가 답했는지와 Dmin 을
// 냅니다. macOS `FilmBaseEstimator.estimate` 와 값을 대조하는 유일한 자리입니다 — 앱으로
// 재면 디코드·현상·UI 가 섞여 어느 단계가 답했는지 알 수 없습니다.
int run_auto_base_probe(int argument_count, const wchar_t* const arguments[]);

}  // namespace negaflow::cli
