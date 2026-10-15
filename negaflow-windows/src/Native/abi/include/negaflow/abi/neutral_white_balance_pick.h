#pragma once

/* The neutral white balance eyedropper: the warmth and tint that make one canvas click grey. */

#include "negaflow/abi/platform.h"
#include "negaflow/abi/develop_output.h"
#include "negaflow/abi/develop_result.h"

#ifdef __cplusplus
extern "C" {
#endif

/* 중립 스포이드의 결과입니다. `status` 는 아래 NF_NEUTRAL_PICK_* 입니다.
   reference 는 찍은 점 주위의 화이트밸런스 입력(linear, 색 모델 직전) 평균이고, warmth/tint 는
   그 점을 중립으로 만드는 값입니다(±4 에서 멈춤). 룩 프리셋의 온도·틴트는 요청에 이미 더해져
   있으므로 그 몫을 빼서 저장하는 것은 호출자 일입니다. */
typedef struct nf_neutral_white_balance_pick_v1 {
    uint32_t struct_size;
    uint32_t status;
    double reference_red;
    double reference_green;
    double reference_blue;
    double warmth;
    double tint;
} nf_neutral_white_balance_pick_v1;

/* 0 성공, 1 현상하지 못함, 2 그 점은 너무 어둡거나 클리핑에 가까워 채널비를 믿을 수 없음. */
#define NF_NEUTRAL_PICK_OK 0U
#define NF_NEUTRAL_PICK_UNAVAILABLE 1U
#define NF_NEUTRAL_PICK_REJECTED 2U

/* 화면의 정착 프리뷰와 같은 입력(raw 프록시·결함 제거·베이스·장면 측정)으로 색 모델 직전까지
   현상하고 `unit_x`/`unit_y`(변형 전 원본 정규 좌표, 0…1, y 아래로)를 잽니다. 결과 화소는 쓰지
   않습니다. */
NF_API nf_status_t NF_CALL nf_pick_neutral_white_balance_v1(
    const nf_develop_export_request_v39* request, double unit_x, double unit_y,
    nf_develop_run_state_v1* run_state, nf_develop_export_result_v3* result,
    nf_neutral_white_balance_pick_v1* picked);

#ifdef __cplusplus
}
#endif
