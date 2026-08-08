# ADR-0017: provenance gate는 Windows 1차 C++와 제3자 payload를 구분한다

- 상태: 채택
- 날짜: 2026-08-04

## 문제

기존 macOS 저장소의 provenance gate는 tracked C/C++ 파일을 전부 외부 native source로 간주해
거부했습니다. 별도 `Negaflow.Windows/`에 직접 작성한 C++20 엔진이 생긴 뒤에도 이 규칙을 그대로 두면
정상적인 Windows source가 CI를 통과할 수 없습니다. 반대로 확장자 전체를 허용하면 vendored code나
binary payload가 Apache-2.0 저장소에 섞이는 것을 막던 경계가 사라집니다.

## 결정

1. C/C++/Objective-C 확장자는 `Negaflow.Windows/src`와 `Negaflow.Windows/tests` 아래에서만 1차 source로
   허용합니다. 다른 위치의 native source는 계속 거부합니다.
2. `vendor`, `vendors`, `third_party`, `third-party` 이름의 디렉터리는 계속 금지합니다. 유일한 예외는
   `Negaflow.Windows/third_party/manifest` 바로 아래의 `.json` component manifest입니다. nested file,
   source, library, archive와 binary payload는 허용하지 않습니다.
3. 금지된 외부 구현 marker와 제3자 source header 검사는 기존 Swift `Sources`, `Tests`, `scripts`뿐 아니라
   `Negaflow.Windows/src`, `tests`, `scripts`에도 적용합니다.
4. reachable Git history의 외부 구현 marker 검사도 Windows source와 test를 포함합니다. 현재 tree만
   지운 뒤 과거 commit에 payload를 남기는 우회를 허용하지 않습니다.
5. 정책은 임시 디렉터리 기반 unit test로 고정합니다. 허용된 두 source root, root 밖 native source,
   source 안 vendor directory, 정확한 top-level component manifest와 nested/payload 거부를 각각 검사합니다.

## 결과

Windows 코어를 first-party source로 명시하면서도 제3자 vendoring 금지는 더 좁고 기계적으로 유지됩니다.
runtime dependency 0, 빈 vcpkg port dependency와 OS API 우선 결정은 바뀌지 않습니다. 앞으로 외부
dependency가 필요하면 이 예외를 넓히는 대신 기존 dependency gate, 라이선스·NOTICE·SBOM 검토를 먼저
통과해야 합니다.

## 검증 한계

경로와 marker 검사는 법률 검토나 코드 유사성 판정을 대신하지 않습니다. source provenance, 공식 문서,
claims 비교와 human review는 각 기능 문서에 계속 기록합니다. JSON manifest를 허용한다는 사실도 그 안의
payload를 자동 승인하지 않습니다.
