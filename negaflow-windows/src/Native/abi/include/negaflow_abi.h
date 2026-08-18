#pragma once

/* 이 헤더는 공개 C ABI 전체를 한 번에 들이는 집계 헤더입니다. 새 소비자는 필요한
   도메인 헤더만 직접 포함하십시오 - 아래 목록이 그 전부이며 각각 단독으로 포함할 수
   있습니다. 선언 본문은 도메인 헤더가 소유하고 이 파일은 아무것도 선언하지 않습니다. */

#include "negaflow/abi/platform.h"
#include "negaflow/abi/build_info.h"
#include "negaflow/abi/develop_enums.h"
#include "negaflow/abi/develop_request_core.h"
#include "negaflow/abi/local_dodge_burn.h"
#include "negaflow/abi/develop_request_scene.h"
#include "negaflow/abi/defect_recipe.h"
#include "negaflow/abi/develop_output.h"
#include "negaflow/abi/develop_result.h"
#include "negaflow/abi/auto_adjust.h"
#include "negaflow/abi/infrared_detect.h"
#include "negaflow/abi/flatbed_detect.h"
#include "negaflow/abi/source_probe.h"
#include "negaflow/abi/soft_proof.h"
#include "negaflow/abi/limits.h"
#include "negaflow/abi/grain_mend_detect.h"
#include "negaflow/abi/film_base_pick.h"
#include "negaflow/abi/develop_entry.h"
