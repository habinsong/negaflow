#pragma once

/* The bounds the engine validator enforces, exported so a UI cannot drift out of them. */

#include "negaflow/abi/platform.h"

#ifdef __cplusplus
extern "C" {
#endif

/* The bounds the engine's own validator enforces. Exported so a UI does not have to
   duplicate them and cannot drift into offering values the engine will refuse. */
typedef struct nf_tone_limits_v1 {
    uint32_t struct_size;
    float maximum_exposure_stops;
    float maximum_tone_control;
    /* 흰색 계열 / 검정 계열만 더 넓습니다 — macOS `DevelopToneRange.whites`·`blacks` 가 `-2...2`
       입니다. 끝점(백점·흑점) 제어라 ±1 로는 밀리지 않는 장면이 있습니다. 이 필드는 기존
       구조체의 패딩 자리에 들어가므로 다른 필드의 오프셋도 struct_size 도 바뀌지 않습니다. */
    float maximum_endpoint_tone_control;
    double minimum_film_emulation_intensity;
    double maximum_film_emulation_intensity;
} nf_tone_limits_v1;

/* The range a manual film base is clamped into. A UI that guesses these offers a value
   the engine silently moves, which is harder to notice than a refusal. */
typedef struct nf_negative_limits_v1 {
    uint32_t struct_size;
    float minimum_manual_dmin;
    float maximum_manual_dmin;
} nf_negative_limits_v1;

/* 설정 창 "메모리 캐시" 가 고른 상주 한도입니다. 엔진 안의 두 캐시 — 디코드한 원본
   (macOS `cleanedRawImage`)과 프리뷰 raw 프록시(macOS `developed` 몫) — 의 상한을 정합니다.
   단위는 macOS 와 같은 프레임 수이고, 프레임 하나의 값은 엔진이 macOS 와 같은 상수
   (190MB / 170MB)로 셉니다.

   둘 다 0 이면 자동입니다 — 엔진이 설치 메모리에서 macOS 비율로 잡습니다. 한도는 "미리 잡아
   두는 양" 이 아니라 상한이라, 낮추면 다음 축출에서 오래된 것부터 내려놓고 올리면 그만큼 더
   담습니다. 이 함수를 부르지 않으면 자동으로 돕니다. */
typedef struct nf_frame_cache_limits_v1 {
    uint32_t struct_size;
    uint32_t cleaned_raw_frames;
    uint32_t developed_frames;
} nf_frame_cache_limits_v1;

NF_API nf_status_t NF_CALL nf_get_tone_limits_v1(nf_tone_limits_v1* output);

NF_API nf_status_t NF_CALL nf_get_negative_limits_v1(nf_negative_limits_v1* output);

NF_API nf_status_t NF_CALL nf_set_frame_cache_limits_v1(
    const nf_frame_cache_limits_v1* limits);

#ifdef __cplusplus
}
#endif
