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

/* 설정 창 "메모리 캐시" 의 GPU 항목이 고른 상한입니다. `GpuImagePool` 이 잡는 작업 텍스처의
   바이트 상한을 정합니다.

   **왜 RAM 과 따로 있는가** — RAM 캐시 예산(`nf_frame_cache_limits_v1`)은 디코드 원본과
   프리뷰 프록시만 셉니다. GPU 텍스처는 그 어느 쪽도 아니고, 외장 그래픽에서는 아예 다른
   물리 메모리(VRAM)에 있습니다. 48MP 한 장이 float32 RGBA 로 770MB 이고 풀이 최대 여섯
   장이라, 막지 않으면 한 풀이 4.6GB 를 잡습니다.

   0 이면 자동입니다 — 외장은 DXGI 가 이 프로세스에 준 예산에서, 내장은 설치 RAM 에서
   몫을 뗍니다. 상한은 "미리 잡아 두는 양" 이 아니라 상한이라, 넘으면 풀이 텍스처를 만들지
   않고 그 진입점은 CPU 경로로 갑니다. */
typedef struct nf_gpu_cache_limit_v1 {
    uint32_t struct_size;
    uint32_t reserved;
    uint64_t limit_bytes;
} nf_gpu_cache_limit_v1;

/* 설정 창이 GPU 항목을 그리는 데 필요한 값입니다. GPU 가 없으면 `has_gpu` 가 0 이고, 그때
   설정 창은 그 줄을 아예 내지 않습니다. */
typedef struct nf_gpu_cache_info_v1 {
    uint32_t struct_size;
    uint32_t has_gpu;
    uint32_t is_integrated;
    uint32_t reserved;
    /* DXGI 가 준 어댑터 이름(UTF-8, NUL 종료). 표시용입니다. */
    char adapter_description[160];
    uint64_t dedicated_video_memory_bytes;
    /* `IDXGIAdapter3::QueryVideoMemoryInfo(LOCAL).Budget`. 못 읽으면 0 입니다. */
    uint64_t video_memory_budget_bytes;
    uint64_t automatic_limit_bytes;
    uint64_t effective_limit_bytes;
    uint64_t resident_bytes;
} nf_gpu_cache_info_v1;

NF_API nf_status_t NF_CALL nf_get_tone_limits_v1(nf_tone_limits_v1* output);

NF_API nf_status_t NF_CALL nf_get_negative_limits_v1(nf_negative_limits_v1* output);

NF_API nf_status_t NF_CALL nf_set_frame_cache_limits_v1(
    const nf_frame_cache_limits_v1* limits);

/* 지금 이 프로세스의 메모리 내역입니다. 캐시가 저마다 자기 예산 안에 있어도 프로세스
   총량은 상한을 넘을 수 있어, 그 차이를 눈으로 볼 자리가 필요합니다. */
typedef struct nf_memory_report_v1 {
    uint32_t struct_size;
    uint32_t reserved;
    uint64_t process_private_bytes;
    uint64_t decoded_source_resident_bytes;
    uint64_t decoded_source_budget_bytes;
    uint64_t preview_proxy_resident_bytes;
    uint64_t preview_proxy_budget_bytes;
    uint64_t gpu_pool_resident_bytes;
    uint64_t gpu_pool_limit_bytes;
    uint64_t gpu_system_memory_bytes;
    uint64_t non_cache_overhead_bytes;
    uint64_t automatic_process_ceiling_bytes;
} nf_memory_report_v1;

NF_API nf_status_t NF_CALL nf_set_gpu_cache_limit_v1(const nf_gpu_cache_limit_v1* limit);

NF_API nf_status_t NF_CALL nf_get_memory_report_v1(nf_memory_report_v1* output);

NF_API nf_status_t NF_CALL nf_get_gpu_cache_info_v1(nf_gpu_cache_info_v1* output);

#ifdef __cplusplus
}
#endif
