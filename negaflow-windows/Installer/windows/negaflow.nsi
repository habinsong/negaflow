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
!ifndef BRANDING
  !error "BRANDING is required: makensis -DBRANDING=<branding bitmap directory>"
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

; 제품 이름은 언제나 소문자다.
!define APPNAME "negaflow"
!define EXENAME "Negaflow.Shell.exe"
!define AUMID "Negaflow.Windows_esnvpjf0wq370!App"
!define REGKEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\Negaflow"
!define APP_ICON "${__FILEDIR__}\..\..\src\Shell\Assets\Negaflow.ico"

Name "${APPNAME}"
OutFile "negaflow-${VERSION}-win-${ARCH}.exe"
InstallDir "$LOCALAPPDATA\Negaflow\App"
RequestExecutionLevel user
; 기본값은 NSIS 자기 이름과 판번호를 답니다. 이 제품의 것이 아닙니다.
BrandingText "${APPNAME} ${VERSION}"
Icon "${APP_ICON}"
UninstallIcon "${APP_ICON}"

VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "${APPNAME}"
VIAddVersionKey "FileDescription" "Negaflow for Windows"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "ProductVersion" "${VERSION}"
VIAddVersionKey "LegalCopyright" "Copyright 2026 Song Habin"

; --- 화면 -------------------------------------------------------------------
;
; 기본 MUI 그대로 두면 90 년대 마법사처럼 보인다. 바꾸는 것은 넷이다.
;   · 아이콘을 앱 아이콘으로 (투명 배경에서 구운 것)
;   · 환영·완료 화면 왼쪽 판을 짙은 단색 + 워드마크로
;   · 나머지 화면 머리글에 아이콘
;   · 문구를 사람 말로, 여섯 언어로
;
; 비트맵은 `scripts\generate-installer-branding.ps1` 이 앱 아이콘에서 굽는다. NSIS 는 BMP 만
; 받고 알파를 읽지 않으므로, 각 화면의 실제 배경색 위에 미리 합성해 둔 것이다.

!define MUI_ABORTWARNING
!define MUI_ICON "${APP_ICON}"
!define MUI_UNICON "${APP_ICON}"

; 고른 언어를 남깁니다. 남기지 않으면 제거 프로그램은 목록의 첫 언어(영어)로 뜹니다 —
; 설치는 한국어로 했는데 제거만 영어가 되면 같은 UI/UX 가 아닙니다.
!define MUI_LANGDLL_REGISTRY_ROOT "HKCU"
!define MUI_LANGDLL_REGISTRY_KEY "${REGKEY}"
!define MUI_LANGDLL_REGISTRY_VALUENAME "InstallerLanguage"
; 남긴 값이 있어도 설치 때는 **언제나** 언어를 묻습니다. 이 정의가 없으면 MUI 가 두 번째
; 설치부터 대화상자를 건너뛰어, 언어를 바꾸려는 사용자가 바꿀 자리를 잃습니다.
!define MUI_LANGDLL_ALWAYSSHOW

; 비트맵은 두 배 크기로 굽고 칸에 맞춥니다. 마법사는 화면 배율을 따라 커지는데 비트맵은
; 그대로 그려지므로, 원래 크기로 두면 왼쪽 판 아래에 흰 여백이 남고 머리글 아이콘이
; 뭉갭니다. `AspectFill` 은 비율을 지키며 칸을 채웁니다.
!define MUI_HEADERIMAGE
!define MUI_HEADERIMAGE_RIGHT
!define MUI_HEADERIMAGE_BITMAP "${BRANDING}\header.bmp"
!define MUI_HEADERIMAGE_BITMAP_STRETCH AspectFitHeight
!define MUI_HEADERIMAGE_UNBITMAP "${BRANDING}\header.bmp"
!define MUI_HEADERIMAGE_UNBITMAP_STRETCH AspectFitHeight

!define MUI_WELCOMEFINISHPAGE_BITMAP "${BRANDING}\welcome.bmp"
!define MUI_WELCOMEFINISHPAGE_BITMAP_STRETCH FitControl
!define MUI_UNWELCOMEFINISHPAGE_BITMAP "${BRANDING}\welcome.bmp"
!define MUI_UNWELCOMEFINISHPAGE_BITMAP_STRETCH FitControl

!define MUI_WELCOMEPAGE_TITLE "$(NegaflowWelcomeTitle)"
!define MUI_WELCOMEPAGE_TEXT "$(NegaflowWelcomeText)"
!define MUI_FINISHPAGE_TITLE "$(NegaflowFinishTitle)"
!define MUI_FINISHPAGE_TEXT "$(NegaflowFinishText)"
!define MUI_FINISHPAGE_RUN "$WINDIR\explorer.exe"
!define MUI_FINISHPAGE_RUN_PARAMETERS "shell:AppsFolder\${AUMID}"
!define MUI_FINISHPAGE_RUN_TEXT "$(NegaflowFinishRun)"
; 마음에 들면 프로젝트에 별 하나. 기본은 꺼짐입니다.
!define MUI_FINISHPAGE_SHOWREADME ""
!define MUI_FINISHPAGE_SHOWREADME_NOTCHECKED
!define MUI_FINISHPAGE_SHOWREADME_TEXT "$(NegaflowFinishStar)"
!define MUI_FINISHPAGE_SHOWREADME_FUNCTION OpenProjectPage

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

; --- 제거 마법사 -------------------------------------------------------------
;
; 설치와 **같은 화면**을 씁니다 - 환영 · 확인 · 진행 · 완료. 아이콘도 왼쪽 판도 머리글
; 비트맵도 위에서 정한 그대로입니다. MUI2 는 페이지를 하나 꽂을 때마다 제목·본문 정의를
; 지우므로, 제거용 문구는 여기서 다시 겁니다.
!define MUI_WELCOMEPAGE_TITLE "$(NegaflowUninstallWelcomeTitle)"
!define MUI_WELCOMEPAGE_TEXT "$(NegaflowUninstallWelcomeText)"
!define MUI_FINISHPAGE_TITLE "$(NegaflowUninstallFinishTitle)"
!define MUI_FINISHPAGE_TEXT "$(NegaflowUninstallFinishText)"
!insertmacro MUI_UNPAGE_WELCOME
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH

; 언어는 설치를 시작할 때 고른다. 먼저 적은 것이 목록의 기본값이다.
!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "Korean"
!insertmacro MUI_LANGUAGE "Japanese"
!insertmacro MUI_LANGUAGE "SimpChinese"
!insertmacro MUI_LANGUAGE "French"
!insertmacro MUI_LANGUAGE "German"

LangString NegaflowWelcomeTitle ${LANG_ENGLISH} "negaflow for Windows"
LangString NegaflowWelcomeText  ${LANG_ENGLISH} "Import a scan or a camera copy, measure the film base, invert it, and develop it. Color and black-and-white, negative and positive. Your original file is never rewritten.$\r$\n$\r$\nEverything negaflow needs is in this installer, and it writes only to your own user profile.$\r$\n$\r$\nScanner controls appear once you install the separate scanner plug-in."
LangString NegaflowFinishTitle  ${LANG_ENGLISH} "negaflow is ready"
LangString NegaflowFinishText   ${LANG_ENGLISH} "You'll find it in the Start menu.$\r$\n$\r$\nTo use a scanner, install negaflow-scanner-sane as well."
LangString NegaflowFinishRun    ${LANG_ENGLISH} "Open negaflow"
LangString NegaflowFinishStar   ${LANG_ENGLISH} "Star negaflow on GitHub"
LangString NegaflowUninstallLink ${LANG_ENGLISH} "Uninstall negaflow"

LangString NegaflowWelcomeTitle ${LANG_KOREAN} "negaflow for Windows"
LangString NegaflowWelcomeText  ${LANG_KOREAN} "스캔한 필름이나 카메라로 복사한 필름을 가져와 베이스를 재고, 반전하고, 현상합니다. 컬러와 흑백, 네거티브와 포지티브를 모두 다룹니다. 원본 파일은 고쳐 쓰지 않습니다.$\r$\n$\r$\nnegaflow 에 필요한 것은 이 설치 파일에 전부 들어 있고, 사용자 폴더에만 씁니다.$\r$\n$\r$\n스캐너 조작은 별도의 스캐너 플러그인을 설치하면 나타납니다."
LangString NegaflowFinishTitle  ${LANG_KOREAN} "negaflow 준비 완료"
LangString NegaflowFinishText   ${LANG_KOREAN} "시작 메뉴에서 열 수 있습니다.$\r$\n$\r$\n스캐너를 쓰려면 negaflow-scanner-sane 도 설치하십시오."
LangString NegaflowFinishRun    ${LANG_KOREAN} "negaflow 열기"
LangString NegaflowFinishStar   ${LANG_KOREAN} "GitHub 에서 negaflow 에 별 남기기"
LangString NegaflowUninstallLink ${LANG_KOREAN} "negaflow 제거"

LangString NegaflowWelcomeTitle ${LANG_JAPANESE} "negaflow for Windows"
LangString NegaflowWelcomeText  ${LANG_JAPANESE} "スキャンしたフィルムやカメラで複写したフィルムを読み込み、ベースを測り、反転して現像します。カラーとモノクロ、ネガとポジのどちらにも対応します。元のファイルは書き換えません。$\r$\n$\r$\n必要なものはこのインストーラーに揃っており、ユーザーフォルダーだけに書き込みます。$\r$\n$\r$\nスキャナーの操作は、別のスキャナープラグインを入れると現れます。"
LangString NegaflowFinishTitle  ${LANG_JAPANESE} "negaflow の準備ができました"
LangString NegaflowFinishText   ${LANG_JAPANESE} "スタートメニューから開けます。$\r$\n$\r$\nスキャナーを使うには negaflow-scanner-sane も入れてください。"
LangString NegaflowFinishRun    ${LANG_JAPANESE} "negaflow を開く"
LangString NegaflowFinishStar   ${LANG_JAPANESE} "GitHub で negaflow にスターを付ける"
LangString NegaflowUninstallLink ${LANG_JAPANESE} "negaflow のアンインストール"

LangString NegaflowWelcomeTitle ${LANG_SIMPCHINESE} "negaflow for Windows"
LangString NegaflowWelcomeText  ${LANG_SIMPCHINESE} "导入扫描的胶片或用相机翻拍的胶片，测量片基、反转并进行显影。彩色与黑白、负片与正片均可处理。原始文件不会被改写。$\r$\n$\r$\nnegaflow 所需的一切都包含在此安装程序中，且只写入你的用户目录。$\r$\n$\r$\n安装单独的扫描仪插件后，扫描仪控件才会出现。"
LangString NegaflowFinishTitle  ${LANG_SIMPCHINESE} "negaflow 已就绪"
LangString NegaflowFinishText   ${LANG_SIMPCHINESE} "可从开始菜单打开。$\r$\n$\r$\n若要使用扫描仪，请一并安装 negaflow-scanner-sane。"
LangString NegaflowFinishRun    ${LANG_SIMPCHINESE} "打开 negaflow"
LangString NegaflowFinishStar   ${LANG_SIMPCHINESE} "在 GitHub 上为 negaflow 点星"
LangString NegaflowUninstallLink ${LANG_SIMPCHINESE} "卸载 negaflow"

LangString NegaflowWelcomeTitle ${LANG_FRENCH} "negaflow pour Windows"
LangString NegaflowWelcomeText  ${LANG_FRENCH} "Importez un scan ou une reproduction au boîtier, mesurez la base du film, inversez-la et développez. Couleur et noir et blanc, négatif et positif. Votre fichier d'origine n'est jamais réécrit.$\r$\n$\r$\nTout ce dont negaflow a besoin se trouve dans ce programme d'installation, qui n'écrit que dans votre profil utilisateur.$\r$\n$\r$\nLes commandes du scanner apparaissent une fois le module scanner installé séparément."
LangString NegaflowFinishTitle  ${LANG_FRENCH} "negaflow est prêt"
LangString NegaflowFinishText   ${LANG_FRENCH} "Vous le trouverez dans le menu Démarrer.$\r$\n$\r$\nPour utiliser un scanner, installez également negaflow-scanner-sane."
LangString NegaflowFinishRun    ${LANG_FRENCH} "Ouvrir negaflow"
LangString NegaflowFinishStar   ${LANG_FRENCH} "Mettre une étoile à negaflow sur GitHub"
LangString NegaflowUninstallLink ${LANG_FRENCH} "Désinstaller negaflow"

LangString NegaflowWelcomeTitle ${LANG_GERMAN} "negaflow für Windows"
LangString NegaflowWelcomeText  ${LANG_GERMAN} "Scan oder Kamera-Reproduktion importieren, die Filmbasis messen, invertieren und entwickeln. Farbe und Schwarzweiß, Negativ und Positiv. Ihre Originaldatei wird nie überschrieben.$\r$\n$\r$\nAlles, was negaflow braucht, steckt in diesem Installationsprogramm, und es schreibt ausschließlich in Ihr Benutzerprofil.$\r$\n$\r$\nScanner-Bedienelemente erscheinen, sobald das separate Scanner-Plug-in installiert ist."
LangString NegaflowFinishTitle  ${LANG_GERMAN} "negaflow ist bereit"
LangString NegaflowFinishText   ${LANG_GERMAN} "Sie finden es im Startmenü.$\r$\n$\r$\nFür einen Scanner installieren Sie zusätzlich negaflow-scanner-sane."
LangString NegaflowFinishRun    ${LANG_GERMAN} "negaflow öffnen"
LangString NegaflowFinishStar   ${LANG_GERMAN} "negaflow auf GitHub mit einem Stern versehen"
LangString NegaflowUninstallLink ${LANG_GERMAN} "negaflow deinstallieren"

LangString NegaflowUninstallWelcomeTitle ${LANG_ENGLISH} "Remove negaflow"
LangString NegaflowUninstallWelcomeText ${LANG_ENGLISH} "This removes negaflow from your user profile: the application folder, its package registration, and the Start-menu shortcut.$\r$\n$\r$\nYour photos, libraries, and settings are not touched, and the scanner plug-in negaflow-scanner-sane is removed separately."
LangString NegaflowUninstallFinishTitle ${LANG_ENGLISH} "negaflow has been removed"
LangString NegaflowUninstallFinishText ${LANG_ENGLISH} "The application folder and its package registration are gone.$\r$\n$\r$\nYour photos and libraries stayed where they were. To remove scanner support as well, uninstall negaflow-scanner-sane."

LangString NegaflowUninstallWelcomeTitle ${LANG_KOREAN} "negaflow 제거"
LangString NegaflowUninstallWelcomeText ${LANG_KOREAN} "사용자 폴더에 있는 negaflow 를 지웁니다 — 앱 폴더, 패키지 등록, 시작 메뉴 바로 가기입니다.$\r$\n$\r$\n사진과 라이브러리, 설정은 건드리지 않으며, 스캐너 플러그인 negaflow-scanner-sane 은 따로 제거합니다."
LangString NegaflowUninstallFinishTitle ${LANG_KOREAN} "negaflow 를 제거했습니다"
LangString NegaflowUninstallFinishText ${LANG_KOREAN} "앱 폴더와 패키지 등록을 지웠습니다.$\r$\n$\r$\n사진과 라이브러리는 그대로 있습니다. 스캐너 기능까지 지우려면 negaflow-scanner-sane 도 제거하십시오."

LangString NegaflowUninstallWelcomeTitle ${LANG_JAPANESE} "negaflow のアンインストール"
LangString NegaflowUninstallWelcomeText ${LANG_JAPANESE} "ユーザーフォルダーの negaflow を削除します — アプリフォルダー、パッケージ登録、スタートメニューのショートカットです。$\r$\n$\r$\n写真・ライブラリ・設定には触れません。スキャナープラグイン negaflow-scanner-sane は別に削除します。"
LangString NegaflowUninstallFinishTitle ${LANG_JAPANESE} "negaflow を削除しました"
LangString NegaflowUninstallFinishText ${LANG_JAPANESE} "アプリフォルダーとパッケージ登録を削除しました。$\r$\n$\r$\n写真とライブラリはそのままです。スキャナー機能も消すには negaflow-scanner-sane も削除してください。"

LangString NegaflowUninstallWelcomeTitle ${LANG_SIMPCHINESE} "卸载 negaflow"
LangString NegaflowUninstallWelcomeText ${LANG_SIMPCHINESE} "将从你的用户目录中删除 negaflow：应用文件夹、包注册和开始菜单快捷方式。$\r$\n$\r$\n照片、图库和设置不会被改动，扫描仪插件 negaflow-scanner-sane 需另行卸载。"
LangString NegaflowUninstallFinishTitle ${LANG_SIMPCHINESE} "negaflow 已卸载"
LangString NegaflowUninstallFinishText ${LANG_SIMPCHINESE} "应用文件夹和包注册已删除。$\r$\n$\r$\n照片和图库仍在原处。若要一并移除扫描仪功能，请卸载 negaflow-scanner-sane。"

LangString NegaflowUninstallWelcomeTitle ${LANG_FRENCH} "Désinstaller negaflow"
LangString NegaflowUninstallWelcomeText ${LANG_FRENCH} "Ceci supprime negaflow de votre profil utilisateur : le dossier de l'application, son enregistrement de package et le raccourci du menu Démarrer.$\r$\n$\r$\nVos photos, bibliothèques et réglages ne sont pas touchés ; le module scanner negaflow-scanner-sane se désinstalle séparément."
LangString NegaflowUninstallFinishTitle ${LANG_FRENCH} "negaflow a été désinstallé"
LangString NegaflowUninstallFinishText ${LANG_FRENCH} "Le dossier de l'application et son enregistrement de package ont disparu.$\r$\n$\r$\nVos photos et bibliothèques sont restées en place. Pour retirer aussi la prise en charge du scanner, désinstallez negaflow-scanner-sane."

LangString NegaflowUninstallWelcomeTitle ${LANG_GERMAN} "negaflow entfernen"
LangString NegaflowUninstallWelcomeText ${LANG_GERMAN} "Damit wird negaflow aus Ihrem Benutzerprofil entfernt: der Anwendungsordner, seine Paketregistrierung und die Startmenü-Verknüpfung.$\r$\n$\r$\nIhre Fotos, Bibliotheken und Einstellungen bleiben unberührt; das Scanner-Plug-in negaflow-scanner-sane wird separat entfernt."
LangString NegaflowUninstallFinishTitle ${LANG_GERMAN} "negaflow wurde entfernt"
LangString NegaflowUninstallFinishText ${LANG_GERMAN} "Anwendungsordner und Paketregistrierung sind entfernt.$\r$\n$\r$\nIhre Fotos und Bibliotheken sind geblieben. Um auch die Scanner-Unterstützung zu entfernen, deinstallieren Sie negaflow-scanner-sane."

Function OpenProjectPage
  ExecShell "open" "https://github.com/habinsong/negaflow"
FunctionEnd

Function .onInit
  !insertmacro MUI_LANGDLL_DISPLAY
FunctionEnd

Function un.onInit
  ; 설치 때 고른 언어를 그대로 씁니다. 남아 있지 않으면 MUI 가 목록을 띄웁니다.
  !insertmacro MUI_UNGETLANGUAGE
FunctionEnd

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
  ; **앱 바로가기는 만들지 않습니다.** 등록된 MSIX 패키지가 시작 메뉴 항목을 스스로
  ; 내놓습니다. 여기서 하나 더 만들면 `shell:AppsFolder` 같은 자리를 가리키는 항목이
  ; 둘이 되어, 시작 메뉴에 negaflow 가 두 번 뜹니다(실측 2026-08-30 `Get-StartApps`:
  ; `Negaflow` = 이 바로가기, `negaflow` = 패키지). 제거만 둡니다 — 그쪽은 패키지가
  ; 내놓지 않습니다.
  CreateDirectory "$SMPROGRAMS\Negaflow"
  ; 제거는 `설정 > 앱` 에도 등록되지만, 시작 메뉴에서 바로 찾을 자리가 없었습니다.
  ; negaflow 쪽은 같은 폴더를 가리키는 MSIX 패키지 항목이 나란히 떠서 어느 쪽이 진짜
  ; 제거인지 가려지기까지 합니다(MSIX 쪽 제거는 등록만 풀고 파일을 남깁니다).
  CreateShortcut "$SMPROGRAMS\Negaflow\$(NegaflowUninstallLink).lnk" "$INSTDIR\uninstall.exe" "" "$INSTDIR\Assets\Negaflow.ico"

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

  ; 패키지 신원을 막 지운 참이라 **배포 서비스가 아직 이 폴더를 붙들고 있습니다.**
  ; 곧바로 옮기면 공유 위반으로 실패하고, 그러면 제거가 앱 폴더를 통째로 남긴 채
  ; 끝납니다 - 2026-08-27 로컬 CI 가 그렇게 실패했습니다. 손을 뗄 때까지 기다립니다.
  ; 30 초를 넘기면 그때는 정말로 Negaflow 가 떠 있는 것입니다.
  StrCpy $2 0
  negaflow_uninstall_rename:
  ClearErrors
  Rename "$INSTDIR" "$INSTDIR.removing"
  ${If} ${Errors}
    IntOp $2 $2 + 1
    ${If} $2 < 60
      Sleep 500
      Goto negaflow_uninstall_rename
    ${EndIf}
    MessageBox MB_ICONSTOP "Negaflow를 제거할 수 없습니다. 실행 중인 Negaflow를 닫고 다시 시도하십시오." /SD IDOK
    Abort "Negaflow is running."
  ${EndIf}

  ; 1.1.0 까지의 설치본이 남긴 앱 바로가기입니다. 지금은 만들지 않지만, 그 버전에서
  ; 올라온 기계에는 남아 있으므로 이름을 짚어 지웁니다.
  Delete "$SMPROGRAMS\Negaflow\Negaflow.lnk"
  ; 제거 바로가기 이름은 **설치할 때 고른 언어**로 지어졌습니다. 제거를 다른 언어로
  ; 돌리면 이름이 달라 `Delete` 가 빗나가고 시작 메뉴에 죽은 바로가기가 남습니다.
  ; 폴더 안의 바로가기를 모두 지워 그 경우를 없앱니다.
  Delete "$SMPROGRAMS\Negaflow\*.lnk"
  RMDir "$SMPROGRAMS\Negaflow"
  RMDir /r "$INSTDIR.removing"
  DeleteRegKey HKCU "${REGKEY}"
  ; Negaflow is intentionally removed only when App and Plugins are both gone.
  RMDir "$LOCALAPPDATA\Negaflow"
SectionEnd
