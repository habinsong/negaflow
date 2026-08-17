#pragma once

namespace negaflow::cli {

// 실제 스캔 한 장에 자동 검출을 한 번 걸고 단계별 시간을 냅니다. 앱을 띄우지 않고 검출만
// 재는 유일한 자리입니다 — 앱으로 재면 디코드·현상·UI 가 섞여 어디가 무거운지 알 수 없습니다.
int run_grain_mend_detect(int argument_count, const wchar_t* const arguments[]);

}  // namespace negaflow::cli
