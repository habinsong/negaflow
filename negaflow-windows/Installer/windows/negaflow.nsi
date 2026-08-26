; Negaflow Windows user-scope installer.
; SPDX-License-Identifier: Apache-2.0
;
; Build from negaflow-windows/scripts/build-release.ps1. PAYLOAD is an
; unsigned loose-package directory; do not add developer-machine
; paths or the GPL scanner plug-in to this installer.

Unicode true
ManifestDPIAware true
SetCompressor /SOLID lzma

!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "FileFunc.nsh"

!ifndef PAYLOAD
  !error "PAYLOAD is required: makensis -DPAYLOAD=<published directory>"
!endif
!ifndef RUNTIMEPACKAGE
  !error "RUNTIMEPACKAGE is required: makensis -DRUNTIMEPACKAGE=<Windows App Runtime msix>"
!endif
!ifndef VERSION
  !define VERSION "0.0.0"
!endif
!ifndef ARCH
  !define ARCH "x64"
!endif

!define APPNAME "Negaflow"
!define EXENAME "Negaflow.Shell.exe"
!define AUMID "Negaflow.Windows_esnvpjf0wq370!App"
!define REGKEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\Negaflow"
!define APP_ICON "${__FILEDIR__}\..\..\src\Shell\Assets\Negaflow.ico"

Name "${APPNAME}"
OutFile "Negaflow-${VERSION}-${ARCH}-setup.exe"
InstallDir "$LOCALAPPDATA\Negaflow\App"
RequestExecutionLevel user
Icon "${APP_ICON}"
UninstallIcon "${APP_ICON}"

VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "${APPNAME}"
VIAddVersionKey "FileDescription" "Negaflow for Windows"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "ProductVersion" "${VERSION}"
VIAddVersionKey "LegalCopyright" "Copyright 2026 Song Habin"

!define MUI_ABORTWARNING
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "Korean"
!insertmacro MUI_LANGUAGE "English"

Var Staging
Var Backup
Var MovedAside
Var RegisterLog

; 등록이 실패해도 그 이유가 어디에도 남지 않았습니다 - `nsExec::ExecToStack` 이 담아 온
; 출력은 `Pop` 한 레지스터에만 있고, 무인 설치에는 그것을 보여 줄 화면이 없습니다.
; CI 에서 25 분을 기다린 뒤 남은 것이 "설치가 안 끝났다" 한 줄뿐이었던 까닭입니다.
; 실패한 자리와 플러그인 출력을 파일로 남겨, 검증 스크립트가 그대로 찍게 합니다.
!macro LogValue label value
  ClearErrors
  FileOpen $R9 "$RegisterLog" a
  ${IfNot} ${Errors}
    FileSeek $R9 0 END
    FileWrite $R9 "== ${label} = ${value} ==$\r$\n"
    FileClose $R9
  ${EndIf}
!macroend

!macro LogExec label code output
  ClearErrors
  FileOpen $R9 "$RegisterLog" a
  ${IfNot} ${Errors}
    ; `a` 는 파일 끝이 아니라 0 번지에서 엽니다. 옮기지 않으면 뒤 기록이 앞 기록을 덮습니다.
    FileSeek $R9 0 END
    FileWrite $R9 "== ${label} exit=${code} ==$\r$\n${output}$\r$\n"
    FileClose $R9
  ${EndIf}
!macroend

Section "Install"
  ; First complete the new payload beside the live application.  A running
  ; app makes the rename fail, leaving the previous application untouched.
  StrCpy $RegisterLog "$TEMP\negaflow-install-registration.log"
  Delete "$RegisterLog"
  StrCpy $MovedAside "0"
  StrCpy $Staging "$INSTDIR.staging"
  StrCpy $Backup "$INSTDIR.previous"
  RMDir /r "$Staging"
  RMDir /r "$Backup"

  SetOutPath "$Staging"
  File /r "${PAYLOAD}\*.*"
  SetOutPath "$TEMP"

  ; 앱 패키지는 Windows App Runtime 프레임워크에 기대고 있습니다. 그것이 없는 기계에서는
  ; 등록이 `0x80073CF3` 으로 거부되고 - 러너에서 실제로 그렇게 거부됐습니다 - 이 설치
  ; 프로그램은 사용자 권한으로 도는지라 프레임워크를 나중에 깔아 줄 수도 없습니다.
  ; 그래서 Microsoft 서명 프레임워크 패키지를 함께 싣고, **기존 설치를 건드리기 전에**
  ; 먼저 갖춥니다. 여기서 물러나면 이미 깔려 있던 negaflow 는 그대로 남습니다.
  ; `$PLUGINSDIR` 은 설치가 끝나면 스스로 지워지므로 41 MB 가 설치 폴더에 남지 않습니다.
  InitPluginsDir
  File "/oname=$PLUGINSDIR\WindowsAppRuntime.msix" "${RUNTIMEPACKAGE}"
  nsExec::ExecToStack '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$Staging\package-registration.ps1" -Action EnsureRuntime -RuntimePackagePath "$PLUGINSDIR\WindowsAppRuntime.msix"'
  Pop $0
  Pop $1
  !insertmacro LogExec "ensure-runtime" $0 $1
  ${If} $0 != 0
    RMDir /r "$Staging"
    MessageBox MB_ICONSTOP "Windows App Runtime 을 설치할 수 없습니다. Windows 업데이트를 마친 뒤 다시 시도하십시오." /SD IDOK
    Abort "Windows App Runtime installation failed: $1"
  ${EndIf}

  ; --- 느슨한 패키지 등록 허용 ---
  ;
  ; negaflow 는 서명하지 않은 느슨한 패키지로 등록됩니다(ADR-0027 이 코드 서명을 접었습니다).
  ; Windows 는 그 등록을 `AllowDevelopmentWithoutDevLicense` 로 막아 두고, **깨끗한 PC 에는
  ; 그 값이 없습니다.** 개발 기계도 CI 러너도 둘 다 1 이라 여태 드러나지 않았습니다 —
  ; 2026-08-26 CI 로그에 러너 값을 찍어 확인했습니다.
  ;
  ; HKLM 이라 관리자가 필요합니다. 설치 자체는 사용자 영역 그대로 두고 이 한 단계만 올립니다.
  ; NSIS 는 32 비트라 리디렉션을 끄고 64 비트 하이브를 봐야 합니다.
  SetRegView 64
  ReadRegDWORD $2 HKLM "Software\Microsoft\Windows\CurrentVersion\AppModelUnlock" "AllowDevelopmentWithoutDevLicense"
  SetRegView lastused
  ${If} $2 != 1
    ${If} ${Silent}
      ; 무인 설치는 관리자 확인을 띄울 수 없습니다. 건너뛰고 그 사실을 남깁니다.
      !insertmacro LogValue "loose-package-registration" "silent-skipped"
    ${Else}
      MessageBox MB_YESNO|MB_ICONQUESTION "Negaflow 를 등록하려면 Windows 설정을 한 번 바꿔야 합니다.$\n$\n서명하지 않은 앱 패키지의 등록을 허용하는 설정이며 관리자 확인이 필요합니다. 건너뛰면 설치가 등록 단계에서 실패합니다.$\n$\n지금 바꿀까요?" /SD IDYES IDNO SkipUnlock
      ExecShellWait "runas" "$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" '-NoProfile -ExecutionPolicy Bypass -File "$Staging\package-registration.ps1" -Action EnableLoosePackageRegistration' SW_SHOWMINIMIZED
      SkipUnlock:
    ${EndIf}
    SetRegView 64
    ReadRegDWORD $2 HKLM "Software\Microsoft\Windows\CurrentVersion\AppModelUnlock" "AllowDevelopmentWithoutDevLicense"
    SetRegView lastused
    !insertmacro LogValue "loose-package-registration-allowed" $2
  ${EndIf}

  ; A previous loose package points at the live directory. Unregister it
  ; before the atomic directory swap, then register the new manifest below.
  nsExec::ExecToStack '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$Staging\package-registration.ps1" -Action Unregister'
  Pop $0
  Pop $1
  !insertmacro LogExec "unregister-before-swap" $0 $1

  ${If} ${FileExists} "$INSTDIR\*.*"
    ClearErrors
    Rename "$INSTDIR" "$Backup"
    ${If} ${Errors}
      RMDir /r "$Staging"
      MessageBox MB_ICONSTOP "기존 Negaflow를 교체할 수 없습니다. 실행 중인 Negaflow를 닫고 다시 시도하십시오." /SD IDOK
      Abort "Negaflow is running."
    ${EndIf}
    StrCpy $MovedAside "1"
  ${EndIf}

  ClearErrors
  Rename "$Staging" "$INSTDIR"
  ${If} ${Errors}
    RMDir /r "$Staging"
    ${If} $MovedAside == "1"
      Rename "$Backup" "$INSTDIR"
    ${EndIf}
    Abort "The new application could not be installed."
  ${EndIf}

  nsExec::ExecToStack '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$INSTDIR\package-registration.ps1" -Action Register -ManifestPath "$INSTDIR\AppxManifest.xml"'
  Pop $0
  Pop $1
  !insertmacro LogExec "register" $0 $1
  ${If} $0 != 0
    RMDir /r "$INSTDIR"
    ${If} $MovedAside == "1"
      Rename "$Backup" "$INSTDIR"
      ${If} ${FileExists} "$INSTDIR\AppxManifest.xml"
        nsExec::ExecToStack '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$INSTDIR\package-registration.ps1" -Action Register -ManifestPath "$INSTDIR\AppxManifest.xml"'
        Pop $2
        Pop $3
        !insertmacro LogExec "register-rollback" $2 $3
      ${EndIf}
    ${EndIf}
    MessageBox MB_ICONSTOP "Negaflow package identity could not be registered. Windows Developer Mode must allow unsigned loose-package registration." /SD IDOK
    Abort "Package registration failed: $1"
  ${EndIf}
  RMDir /r "$Backup"

  ; Do not create or delete the sibling Plugins directory.  The separately
  ; licensed SANE installer owns %LOCALAPPDATA%\Negaflow\Plugins\sane.
  WriteUninstaller "$INSTDIR\uninstall.exe"
  CreateDirectory "$SMPROGRAMS\Negaflow"
  CreateShortcut "$SMPROGRAMS\Negaflow\Negaflow.lnk" "$WINDIR\explorer.exe" "shell:AppsFolder\${AUMID}" "$INSTDIR\Assets\Negaflow.ico"

  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  WriteRegStr HKCU "${REGKEY}" "DisplayName" "${APPNAME}"
  WriteRegStr HKCU "${REGKEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${REGKEY}" "Publisher" "Song Habin"
  WriteRegStr HKCU "${REGKEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${REGKEY}" "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteRegStr HKCU "${REGKEY}" "QuietUninstallString" '"$INSTDIR\uninstall.exe" /S'
  WriteRegStr HKCU "${REGKEY}" "DisplayIcon" '"$INSTDIR\Assets\Negaflow.ico"'
  WriteRegDWORD HKCU "${REGKEY}" "NoModify" 1
  WriteRegDWORD HKCU "${REGKEY}" "NoRepair" 1
  WriteRegDWORD HKCU "${REGKEY}" "EstimatedSize" $0
SectionEnd

Section "Uninstall"
  nsExec::ExecToStack '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$INSTDIR\package-registration.ps1" -Action Unregister'
  Pop $0
  Pop $1
  ${If} $0 != 0
    MessageBox MB_ICONSTOP "Negaflow package identity could not be removed." /SD IDOK
    Abort "Package unregistration failed: $1"
  ${EndIf}

  ClearErrors
  Rename "$INSTDIR" "$INSTDIR.removing"
  ${If} ${Errors}
    MessageBox MB_ICONSTOP "Negaflow를 제거할 수 없습니다. 실행 중인 Negaflow를 닫고 다시 시도하십시오." /SD IDOK
    Abort "Negaflow is running."
  ${EndIf}

  Delete "$SMPROGRAMS\Negaflow\Negaflow.lnk"
  RMDir "$SMPROGRAMS\Negaflow"
  RMDir /r "$INSTDIR.removing"
  DeleteRegKey HKCU "${REGKEY}"
  ; Negaflow is intentionally removed only when App and Plugins are both gone.
  RMDir "$LOCALAPPDATA\Negaflow"
SectionEnd
