"""설정 값마다 '설정 창 바깥에서 실제로 읽는 곳'이 있는지 셉니다.

읽는 곳이 없으면 그 컨트롤은 저장만 하고 아무 일도 하지 않는 가짜입니다.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SETTINGS_VIEW = "SettingsRootView"

# (설정 이름, 코드에서 찾을 낱말들)
SUBJECTS = [
    ("일반 · 앱 언어", ["preferences.Language", "SetLanguage(", "AppResources.SetLanguage"]),
    ("일반 · 화면 모드", ["preferences.Appearance", ".Appearance ", "SetAppearance("]),
    ("일반 · 개발자 모드", ["DiagnosticTraceSwitches", "preview-trace.on", "shortcut-trace.on", "thumbnail-trace.on"]),
    ("일반 · 메모리 캐시", ["FrameCache", "ApplyResidencySettings"]),
    ("일반 · 지원 번들", ["SupportBundleBuilder", "SupportBundleArchiveWriter"]),
    ("인터페이스 · 캔버스 배경", ["CanvasBackground"]),
    ("인터페이스 · 클리핑 오버레이", ["ClippingOverlayEnabled"]),
    ("인터페이스 · 픽셀 샘플러", ["PixelSamplerEnabled"]),
    ("워크플로 · 스캐너 시뮬레이터", ["ScannerSimulatorEnabled", "SetSimulatorEnabled"]),
    ("워크플로 · 자동 현상", ["DevelopsImportsAutomatically"]),
    ("워크플로 · 미세 입자 자동", ["AutoDefectDetectsMicroSpecks"]),
    ("워크플로 · 미세 입자 가이드", ["GuidedDefectDetectsMicroSpecks"]),
    ("스캔 · 기본 방향", ["DefaultScanRotation", "ApplyDefaultRotation"]),
    ("스캔 · 스캐너 정보", ["PublishScannerCapabilities", "CapabilitiesPublisher"]),
    ("스캔 · 플러그인 승인", ["ScannerPluginTrustStore"]),
    ("디스크 · 저장 위치/폴더", ["DiskStorageLocations", "preferences.Disk", "current.Disk"]),
    ("디스크 · 썸네일 캐시 지우기", ["ClearDiskCacheAsync"]),
    ("디스크 · 백업", ["CreateBackup(", "preferences.Backup", "current.Backup"]),
    ("디스크 · 보존 아카이브", ["LibraryArchiveWriter"]),
    ("내보내기 · 빠른 내보내기", ["ResolvedQuickExport", "quickExportSettings"]),
    ("내보내기 · 무결성 검사", ["ImageContentHash", "VerifyDefectSourceContent"]),
    ("내보내기 · 색상 관리", ["preferences.SoftProof", "softProofPreferences", "ResolvedExport"]),
    ("단축키", ["Shortcuts.Resolve", "current.Shortcuts", "preferences.Shortcuts"]),
]


def main():
    sources = []
    for path in ROOT.joinpath("src").rglob("*.cs"):
        if any(part in {"out", "bin", "obj"} for part in path.parts):
            continue
        sources.append((path.relative_to(ROOT), path.read_text(encoding="utf-8")))

    width = max(len(name) for name, _ in SUBJECTS)
    for name, needles in SUBJECTS:
        hits = []
        for rel, text in sources:
            if SETTINGS_VIEW in rel.name:
                continue
            # 저장 계층은 소비자가 아닙니다. 값을 담아 두기만 합니다.
            if rel.name in {"ShellPreferences.cs", "WorkspacePresentationState.cs",
                            "PresentationSettingsStore.cs"}:
                continue
            if any(needle in text for needle in needles):
                hits.append(str(rel).replace("src\\", ""))
        mark = "OK " if hits else "없음"
        print(f"{mark} {name.ljust(width)}  {len(hits)}곳")
        for hit in sorted(hits)[:4]:
            print(f"      {hit}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
