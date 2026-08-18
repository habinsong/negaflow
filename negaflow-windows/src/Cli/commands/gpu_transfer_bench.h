#pragma once

namespace negaflow::cli {

// 호스트 ↔ GPU 전송 대역폭을 잽니다.
//
// 왜 필요한가 — `docs/audit/04-gpu-plan.md` 3절이 *"24MP float32 RGBA = 384 MB"* 를
// 적으면서 **"위는 바이트 산술이고, 실제 전송 ms 는 아직 재지 않았습니다"** 라고
// 못박아 두었습니다(9절 2번도 같은 것을 미확인으로 답니다). 커널을 아무리 줄여도
// 전송이 지배하면 소용없으므로, 그 자리를 숫자로 채웁니다.
int run_gpu_transfer_bench(int argument_count, const wchar_t* const arguments[]);

}  // namespace negaflow::cli
