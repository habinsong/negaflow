# 적외선 채널이 실기에서 나옵니다 — Epson V700 (GT-X900)

기준일: 2026-08-15

## 무엇을 확인했는가

`2026-08-14` 기록은 IR 을 "원인 확정, 패치 작성, **빌드 미검증**" 으로 남겨 두었습니다.
여기서 그것을 끝냅니다 — SANE 을 실제로 다시 빌드하고, 실제 스캐너로 적외선 채널을 받았습니다.

## 결과

플러그인으로 IR 을 켜고 스캔한 결과입니다.

```
phases: warmingLamp -> scanningRGB -> scanningIR -> complete
hasInfrared: true
irPath:      v700ir.ir.tiff
```

| 항목 | 본 스캔 | IR 채널 |
| --- | --- | --- |
| 파일 | `v700ir.tiff` 720,192 B | `v700ir.ir.tiff` 240,206 B |
| 치수 | 424×283 | 424×283 |
| 심도 | 16-bit RGB | **16-bit, 1채널, photometric 1** |

IR 값의 분포는 min 9 / median 40 / max 65,411 입니다. **65535 에 붙어 있지 않습니다** —
macOS 가 감마 없이 찍었을 때 보고한 "프레임의 2~3.4% 가 65535 에 그대로 잘린다" 는 상태가
아닙니다.

`supportsInfrared` 가 `true` 로 바뀌었고 `disabledReasons` 에서 infrared 항목이 사라졌습니다.

## 세 번 막혔고, 셋 다 다른 곳이었습니다

**① 빌드는 성공하는데 기능만 사라졌습니다.** 패치 009 를 태운 첫 빌드가 끝났고, 소스 헤더에
`SANE_FRAME_IR` 이 분명히 있는데 장치는 여전히 `--mode Lineart|Gray|Color` 를 냈습니다.
빌드 로그에는 아무 말도 없습니다. 만들어진 DLL 안을 뒤져서야 알았습니다.

```
strings cygsane-epson2-1.dll | grep -c '^Infrared$'   →  0
```

epson2 는 `sane/sane.h` 를 include 경로로 찾는데 **이미 깔려 있던 옛 헤더가 먼저** 잡혀
`SANE_FRAME_IR` 이 정의되지 않았고, 모드 목록 항목이 통째로 컴파일에서 빠졌습니다. PKGBUILD 가
소스 트리의 include 를 최우선으로 두도록 고쳤습니다.

**② 백엔드만 바꾸고 프론트엔드를 안 바꿨습니다.** 새 백엔드가 IR 모드를 내주기 시작했는데
플러그인의 IR 패스는 계속 실패했습니다. 원인은 파일 크기 하나로 드러났습니다 —
`239,984 = 424 × 283 × 2`, 즉 **화소 데이터와 정확히 같고 헤더가 0바이트**입니다.

패치 009 의 두 번째 헝크(`scanimage` 가 IR 프레임을 `default: break;` 로 흘려 헤더를 쓰지
않던 것)는 소스에 들어가 있었지만, 돌고 있던 `scanimage.exe` 는 **교체하지 않은 옛 실행
파일**이었습니다. 백엔드 DLL 만 갈아 끼운 탓입니다.

**③ 제 시험이 틀렸습니다.** 감마가 IR 모드에서 거부되는 줄 알았는데,
`User defined (Gamma=1.0)` 이라는 값이 이 장치 목록에 없었을 뿐입니다. V700 의 실제 목록은
`Default | User defined | High density printing | Low density printing | High contrast printing`
입니다. 올바른 값으로는 IR + 감마가 정상 동작합니다. **플러그인이 아니라 시험이 틀렸습니다.**

## 이것이 확인해 준 것

macOS `3d9c3d3`("give the infrared pass the main scan's gamma table and focus")의 이식이
이 장치에서 유효합니다 — 감마와 초점을 IR 패스에 함께 보내도 스캔이 완주하고, IR 신호가 흰쪽
끝에 몰리지 않습니다.

## 확인하지 않은 것

- **필름을 올리지 않은 스캔입니다.** 결함이 있는 실제 필름에서 IR 이 결함을 짚어내는지,
  그 지도가 GrainMend 의 복원과 화소 단위로 맞는지는 확인하지 않았습니다.
- macOS 가 같은 필름에서 낸 IR 채널과의 대조.
- OpticFilm 8100 은 적외선 램프가 없습니다. 이 경로는 8200i 이상에서만 의미가 있습니다.
