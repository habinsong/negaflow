#pragma once

/* Automatic tone and white balance read off a rendered preview. */

#include "negaflow/abi/platform.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Automatic develop settings for one frame.
   These are values to **assign** to the recipe, not deltas to add: running auto twice
   gives the same answer as running it once. Every field is already inside the range the
   engine accepts, so a caller never has to clamp. */
typedef struct nf_auto_adjust_result_v1 {
    uint32_t struct_size;
    uint32_t reserved;
    double exposure;
    double contrast;
    double highlights;
    double shadows;
    double whites;
    double blacks;
    double density;
    double vibrance;
    double warmth;
    double tint;
} nf_auto_adjust_result_v1;

/* Reads a neutral develop — the tone sliders at zero, the frame otherwise properly
   rendered — and returns the settings automatic adjustment would assign.

   The bitmap is BGRA8, exactly what nf_develop_preview_v22 writes, so the caller renders
   a preview it already knows how to render and hands the same buffer straight here. No
   pixels are modified and nothing is retained after the call returns.

   Feeding it a badly rendered frame is not an error and will not be reported as one: auto
   will simply propose its limits in every direction, which is the correct answer for an
   image that far from right. */
NF_API nf_status_t NF_CALL nf_auto_adjust_v1(
    const uint8_t* pixels,
    uint32_t width,
    uint32_t height,
    uint32_t stride_bytes,
    nf_auto_adjust_result_v1* result);

/* v1 과 같되 필름 종류를 받습니다. 자동 톤은 노출 뒤 백분위를 엔진과 같은 노출 숄더로
   예측하는데, 숄더의 헤드룸이 흑백 네거티브만 다릅니다(화이트 0.85). 흑백 네거티브면
   black_and_white_negative 를 0 이 아닌 값으로 넘깁니다. v1 은 컬러 헤드룸으로 계산합니다. */
NF_API nf_status_t NF_CALL nf_auto_adjust_v2(
    const uint8_t* pixels,
    uint32_t width,
    uint32_t height,
    uint32_t stride_bytes,
    uint32_t black_and_white_negative,
    nf_auto_adjust_result_v1* result);

/* 자동 톤 폐루프 한 번입니다. first(nf_auto_adjust_v2 의 결과)를 프레임의 나머지 설정과 함께
   실제로 적용해 렌더한 비트맵을 읽고, 노출(밝힌 경우만)과 화이트를 바로잡은 값을 refined 에
   씁니다. 사용자 커브·색 깊이·스캐너 타깃처럼 자동 톤의 모형 밖에 있는 상호작용을 흡수합니다.
   나머지 필드는 first 그대로입니다. 결정적이라 같은 입력이면 같은 답입니다. */
NF_API nf_status_t NF_CALL nf_auto_tone_refine_v1(
    const uint8_t* pixels,
    uint32_t width,
    uint32_t height,
    uint32_t stride_bytes,
    uint32_t black_and_white_negative,
    const nf_auto_adjust_result_v1* first,
    nf_auto_adjust_result_v1* refined);

/* Rendering objective for checking a proposed automatic tone refinement. */
NF_API nf_status_t NF_CALL nf_auto_tone_score_v1(
    const uint8_t* pixels, uint32_t width, uint32_t height, uint32_t stride_bytes,
    uint32_t adjust_mid, double* score);

/* 0.55: v1 과 같되 중립 현상본(nf_auto_adjust_v2 에 넘긴 비트맵)도 받습니다. 두 비트맵을 칸마다 맞대어 실제로
   새로 날아간 채널(스캐너 타깃·사용자 커브까지 거친 값)을 세고, 채널 한도를 넘으면 키·백점 보정 대신 흰색 →
   노출 순서로 first 의 밝히는 몫을 거둡니다. 넘지 않으면 키·백점 보정을 그대로 내고, 더 밝힌 몫이 넘치는지는 호출
   쪽이 후보를 그려 nf_auto_tone_channel_excess_v1 로 봅니다. 두 비트맵의 크기가 다르면 v1 과 같습니다. */
NF_API nf_status_t NF_CALL nf_auto_tone_refine_v2(
    const uint8_t* neutral_pixels,
    uint32_t neutral_width,
    uint32_t neutral_height,
    uint32_t neutral_stride_bytes,
    const uint8_t* pixels,
    uint32_t width,
    uint32_t height,
    uint32_t stride_bytes,
    uint32_t black_and_white_negative,
    const nf_auto_adjust_result_v1* first,
    nf_auto_adjust_result_v1* refined);

/* 0.55: 렌더한 비트맵에서 중립 현상본에 없던 채널 클리핑이 자동 톤의 한도(0.5%)를 넘는 양입니다(넘지 않으면 0).
   폐루프가 후보를 고를 때 이 값이 작은 쪽을 먼저 고르고, 같으면 nf_auto_tone_score_v1 을 봅니다. 두 비트맵의
   칸이 맞지 않으면 *excess 에 음수를 씁니다. */
NF_API nf_status_t NF_CALL nf_auto_tone_channel_excess_v1(
    const uint8_t* neutral_pixels,
    uint32_t neutral_width,
    uint32_t neutral_height,
    uint32_t neutral_stride_bytes,
    const uint8_t* pixels,
    uint32_t width,
    uint32_t height,
    uint32_t stride_bytes,
    double* excess);

/* 0.55: 채널 한도가 폐루프에서 쓰는 두 바닥입니다. exposure_floor 는 노출을 내릴 수 있는 아래 끝(중립 현상본에서 채널을
   보지 않고 푼 노출 − 1 스톱, 0 아래로는 내리지 않음 — 그 노출이 이미 음수면 그 값), key_budget_stops 는 확인 렌더의
   장면 키에서 더 어둡게 해도 되는 몫(1 스톱 − 첫 계산이 그 노출보다 이미 낮춘 몫)입니다. first_exposure 는 nf_auto_adjust_v2
   가 준 노출입니다. */
NF_API nf_status_t NF_CALL nf_auto_tone_channel_limits_v1(
    const uint8_t* neutral_pixels,
    uint32_t neutral_width,
    uint32_t neutral_height,
    uint32_t neutral_stride_bytes,
    uint32_t black_and_white_negative,
    double first_exposure,
    double* exposure_floor,
    double* key_budget_stops);

/* 0.55: 렌더한 비트맵의 장면 키(선형 휘도의 로그 평균, 자동 톤이 맞추는 값)입니다. */
NF_API nf_status_t NF_CALL nf_auto_tone_scene_key_v1(
    const uint8_t* pixels, uint32_t width, uint32_t height, uint32_t stride_bytes, double* key);

#ifdef __cplusplus
}
#endif
