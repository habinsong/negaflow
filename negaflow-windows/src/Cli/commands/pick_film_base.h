#pragma once

namespace negaflow::cli {

// 원본 한 장의 정규 좌표에서 FilmBasePicker.sample 을 한 번 겁니다.
// 앱 스포이드와 같은 decode + sample 경로입니다.
int run_pick_film_base(int argument_count, const wchar_t* const arguments[]);

}  // namespace negaflow::cli
