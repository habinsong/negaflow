#pragma once

/* The film base eyedropper: Dmin transmittance under one canvas click. */

#include "negaflow/abi/platform.h"

#ifdef __cplusplus
extern "C" {
#endif

/* 필름 베이스 스포이드의 결과입니다. `status` 는 nf_film_base_pick_status_v1 입니다. */
typedef struct nf_film_base_pick_v1 {
    uint32_t struct_size;
    uint32_t status;
    float red;
    float green;
    float blue;
} nf_film_base_pick_v1;

/* 0 성공, 1 이미지를 읽지 못함, 2 그 자리는 필름 베이스가 아님. */
#define NF_FILM_BASE_PICK_OK 0U
#define NF_FILM_BASE_PICK_INVALID_IMAGE 1U
#define NF_FILM_BASE_PICK_IMPLAUSIBLE 2U

/* 사용자가 캔버스에서 미노광 필름 베이스를 클릭한 자리의 Dmin 투과율을 냅니다.
   `unit_x`/`unit_y` 는 0…1 표시 정규 좌표이며 y 는 아래로 커집니다(화면 관례).
   `film_type` 은 0 컬러, 1 흑백입니다. 클릭이 필름 밖(검정 띠·빈 베드)이면
   NF_FILM_BASE_PICK_IMPLAUSIBLE 를 내고 호출부는 Dmin 을 바꾸지 않습니다 - 그 값을
   Dmin 으로 앉히면 반전이 전 구간 클리핑되어 사진이 통째로 검게 죽습니다. */
NF_API nf_status_t NF_CALL nf_pick_film_base_v1(
    const wchar_t* source_path,
    double unit_x,
    double unit_y,
    uint32_t film_type,
    nf_film_base_pick_v1* result);

#ifdef __cplusplus
}
#endif
