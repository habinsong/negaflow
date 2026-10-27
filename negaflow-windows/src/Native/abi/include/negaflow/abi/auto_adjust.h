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

#ifdef __cplusplus
}
#endif
