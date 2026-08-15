# 취소와 진행률 — ABI v22 / 0.28

기준일: 2026-08-10

## 왜

`next-steps.md` 가 오래 적어 둔 공백입니다: **"취소와 진행률은 아직 ABI 에 없습니다."**
실제 스캔 해상도에서 미리보기 한 번이 수백 ms~수 초이고, 슬라이더를 드래그하면 이미 지나간
상태의 렌더가 끝날 때까지 다음 요청이 기다립니다. export 는 더 길고 그동안 사용자에게 보여
줄 수 있는 것이 없었습니다.

## 무엇

호출자가 소유하는 정수 세 개를 공유합니다. 콜백이 경계를 넘지 않습니다.

```c
typedef struct nf_develop_run_state_v1 {
    uint32_t struct_size;
    uint32_t cancel_requested;   /* 호출자만 씀 */
    uint32_t stage;              /* 엔진만 씀 */
    uint32_t progress_permille;  /* 엔진만 씀, 0...1000 */
} nf_develop_run_state_v1;
```

이 모양을 고른 이유는 WinUI 3 의 STA 모델입니다. 콜백을 받으면 델리게이트 수명, 재진입,
스레드 소유권을 전부 계약에 넣어야 합니다. 정수 세 개면 작업자 스레드가 쓰고 UI 스레드가
자기 타이머로 읽는 것으로 끝나며, 살려 둘 것은 이 struct 뿐입니다.

새 진입점은 v21 요청 struct 를 그대로 씁니다. **레시피는 바뀌지 않았고 바뀐 것은 실행 제어**
이므로 같은 struct 를 이름만 바꿔 복제하지 않았습니다.

```c
nf_status_t nf_develop_export_v22(
    const nf_develop_export_request_v21* request,
    nf_develop_run_state_v1* run_state,      /* null 이면 v21 과 같은 동작 */
    nf_develop_export_result_v3* result);
```

`nf_develop_export_result_v3` 는 v2 의 모든 필드를 같은 offset 에 두고 `cancelled` 를 덧붙입니다.
취소를 문자열 비교가 아니라 필드로 답하기 위해서입니다. offset 은 네이티브 `static_assert` 와
관리 `sizeof` 검사 양쪽에서 고정합니다.

## 취소가 걸리는 지점

- 요청 검증 직후 (이미 취소된 요청은 파일을 열지도 않습니다)
- 선택적 source SHA-256 해싱 중 — 기존 `std::stop_token` 경로 재사용
- **TIFF 디코드 중 행 덩어리마다** — 기존 `stop_token` + progress observer 재사용
- 이후 모든 단계 경계

**게시가 시작된 뒤에는 확인하지 않습니다.** 반쪽짜리 파일을 남기지 않기 위한 의도적 선택이며
헤더에 그렇게 적어 두었습니다. 취소된 실행은 목적지 파일도, 미리보기 픽셀도 남기지 않습니다.

**GrainMend 안에도 확인 지점이 있습니다.** 실제 스캔에서 이 단계만 초 단위이므로 단계 경계에서만
멈추면 의미가 없습니다. 채널×반경 9번의 morphology 패스 사이, scratch 각도 묶음 사이, 그리고
전체 해상도 타일마다 확인합니다. 취소된 GrainMend 는 다른 실패와 마찬가지로 픽셀을 폐기하므로
반쯤 복원된 프레임이 다음 단계로 넘어가지 않습니다.

나머지 공간 필터(FilmScanDenoise, Texture, Local Dodge/Burn)는 아직 단계 경계에서만 멈춥니다.

## 진행률

`plan_total_cost` 가 **이 요청이 실제로 실행할 단계만** 더해 분모를 만듭니다. GrainMend 를 끈
프레임은 시간의 대부분이 디코드와 게시에 있고, 고정 단계 목록으로 계산한 진행률은 그것을
반영하지 못합니다. 가중치는 실제 촬영본 측정에서 가져온 ms 단위 추정치이고 **진행 막대만**
움직입니다. 어떤 결과도 이 숫자에 의존하지 않습니다.

되돌아가지 않으며, 성공했을 때만 1000 에 도달합니다.

## 관리 계층

`DevelopRun` 이 상태를 GC 힙이 아니라 `NativeMemory.AllocZeroed` 로 잡습니다. 긴 블로킹 호출
동안 관리 객체를 고정해 두지 않기 위해서입니다. `CancellationToken` 을 주면 등록이 자동으로
`Cancel()` 을 부릅니다. `Dispose` 는 등록을 먼저 정리하고 — 진행 중인 콜백이 끝날 때까지
기다립니다 — 그 다음 해제하므로 취소 콜백이 해제된 메모리를 건드릴 수 없습니다.

```csharp
using var run = new DevelopRun(cancellationToken);
DevelopExportResult result = NativeDevelopExporter.Run(request, run);
if (result.Cancelled) { /* 실패가 아니라 취소 */ }
```

**호출이 돌아오기 전에 `Dispose` 하지 마십시오.** 네이티브가 해제된 주소를 읽습니다.

## 검증 (2026-08-10)

- x64 Debug/Release 네이티브 CTest **57/57**
- Interop **139 assertions**, ABI `0.28`, x64 Debug/Release
- Catalog **583**, Shell **317** assertions, Debug/Release, 경고 0·오류 0
- ARM64 Release 네이티브·관리 전체 graph 교차 빌드, `Negaflow.Native.dll` PE machine `0xAA64`
  (실기 실행 아님)

**실제 촬영 컬러 네거티브 (Plustek OpticFilm 8100, 5088×3401 16-bit) 로 확인한 것:**

- 사전 래치: `cancelled=1`, `failure_name="cancelled"`, 목적지 파일 없음, 미리보기 버퍼 무변경
- **실행 중 래치**: 다른 스레드가 첫 단계 보고를 관측한 뒤 래치를 세워 `decode` 단계에서
  **60.3 ms** 만에 반환. 같은 입력의 취소하지 않은 export 는 **3,323 ms**. 파일 미게시
- 미래치 실행: `progress_permille` 이 정확히 `1000`, 마지막 보고 단계가 `output`, 파일 게시됨
- run state `null`: v21 과 같은 동작
- `struct_size` 를 줄여 넘기면 `NF_STATUS_STRUCT_TOO_SMALL`

**GrainMend 내부 취소도 같은 프레임에서 측정했습니다.**

| | wall |
|---|---|
| GrainMend 켠 미리보기, 취소 없음 | **2,014.7 ms** |
| GrainMend 진입 직후 래치 | **835.0 ms** |

취소 전 단계 합이 약 722 ms 이므로, GrainMend 는 약 1,290 ms 를 다 돌지 않고 약 113 ms 만에
멈췄습니다. export 요청이었으므로 뒤따르는 2,576 ms 게시도 실행되지 않았고 파일도 남지 않았습니다.

**셸의 미리보기 조정자가 이것을 사용합니다.** 새 요청이 들어오면 돌고 있던 렌더를 즉시 취소하고,
취소된 결과는 픽셀이 없으므로 화면에 배달하지 않습니다. "마지막 요청은 반드시 그려진다" 는 기존
계약은 그대로입니다. 실행 손잡이의 수명은 렌더 루프가 같은 lock 아래에서 소유하므로,
`isRunning` 인 동안 취소할 대상이 비어 있는 순간이 없습니다.

macOS 의 취소·진행률 UX 와의 화면 동작 비교, WinUI 버튼·진행 막대 연결,
FilmScanDenoise/Texture/Local Dodge/Burn 내부 취소는 아직입니다.
