# 다음 세션 시작 프롬프트

아래 내용을 그대로 복사해서 새 세션에 붙여 넣으세요.

---

negaflow 필름 시뮬레이션 작업을 이어서 해줘. 이전 세션이 토큰 한도로 중단됐어.

**먼저 `docs/research/film-simulation/09-handoff.md` 를 읽어.** 거기에 현재 상태, 남은 작업,
그리고 이미 끝낸 웹 조사 결과(A등급 데이터시트 수치)가 전부 정리돼 있다. **웹 검색은 하지 마.**
필요한 수치는 그 문서 6절에 다 있다.

요약하면:

- Digital B&W 가 "이미지 로드 실패"로 죽던 버그는 원인을 찾아서 고쳤다
  (`CIBlendWithAlpha` 라는 없는 CIFilter 이름 → Core Image 가 빈 이미지를 반환 → 프레임 소멸).
- 흑백 경로는 컬러와 같은 구조로 전면 재작성했고, 라우팅도 잠갔다
  (필름 룩은 Digital Color / Digital B&W 에서만, 프로세스에 맞는 종류만).
- **아직 안 한 일이 두 가지다:**
  1. 마지막 수정 이후 빌드/테스트를 돌리지 않았다. 새로 쓴
     `Tests/ChromabaseTests/DigitalBWFilmLookTests.swift` 는 한 번도 실행한 적이 없다.
  2. 이전 에이전트가 추가한 **컬러 31종의 개성 검토가 미착수**다.
     확실한 오류 몇 개는 09-handoff.md 4절 2번에 구체적으로 적어 뒀다
     (특히 Vision3 헐레이션 — 지금 값은 Vision3 가 아니라 CineStill 을 재현한다).

순서:

1. `swift build` → `swift test --filter DigitalBWFilmLookTests` → `swift test` 로 회귀 확인
2. 09-handoff.md 4절 2번의 컬러 오류들 수정
3. `scripts/check-swift-concurrency.sh` (CI 게이트)
4. **앱 릴리즈 스크립트로 빌드** — 내가 마지막에 요청한 단계다

기존 11종(컬러 슬라이드 3 + 컬러 네거티브 8)은 문제 없으니 건드리지 마.
커밋은 내가 시키기 전까지 하지 마.
