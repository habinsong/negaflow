#pragma once

namespace negaflow::cli {

// 프리뷰 한 장을 실제 파이프라인(`develop_preview`)으로 뽑고 단계별 표를 찍습니다.
// `--develop-negative-tiff` 는 `imaging::` 을 직접 불러 `run_develop` 을 지나지 않으므로
// 그 경로로는 단계별 표가 나오지 않습니다.
int run_develop_timing(int argument_count, const wchar_t* const arguments[]);

}  // namespace negaflow::cli
