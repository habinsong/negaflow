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
