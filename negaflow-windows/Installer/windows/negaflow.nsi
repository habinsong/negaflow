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
!include "TextFunc.nsh"

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

; --- 최소 Windows 빌드 -------------------------------------------------------
;
; 앱 패키지는 `TargetDeviceFamily MinVersion` 으로 최소 빌드를 못박고 있고, 그보다 낮은
; 기계에서는 `Add-AppxPackage -Register` 가 등록을 거부합니다. 그것을 미리 보는 자리가
; 없었던 탓에 Windows 10 22H2(빌드 19045) 는 파일을 다 풀고 프레임워크까지 깐 뒤
; **맨 마지막 등록 단계**에서 실패했고, 그 다음 줄이 설치 폴더를 지웠습니다(QA 2026-08-31).
;
; 숫자를 여기 적으면 매니페스트와 어긋납니다. 함께 싣는 매니페스트에서 컴파일 때 읽습니다 —
; 매니페스트가 최소 빌드를 올리면 이 게이트도 같이 올라갑니다. 그 줄이 없으면 컴파일이
; 여기서 멈춥니다.
!searchparse /file "${PAYLOAD}\AppxManifest.xml" `MinVersion="10.0.` MIN_OS_BUILD `.`

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
; 고른 폴더가 안전한지 **다음을 누를 때** 봅니다. 아래 `VerifyInstallDirectory` 참고 —
; 제거가 이 폴더를 통째로 지우기 때문에 아무 폴더나 받으면 안 됩니다.
!define MUI_PAGE_CUSTOMFUNCTION_LEAVE VerifyInstallDirectory
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
LangString NegaflowNeedsWindows ${LANG_ENGLISH} "negaflow needs Windows 11 build ${MIN_OS_BUILD} or later.$\r$\n$\r$\nNothing has been installed. This PC reports build:"
LangString NegaflowRegisterFailed ${LANG_ENGLISH} "negaflow could not register its application package.$\r$\n$\r$\nThe error, and the file that keeps the full record:"

LangString NegaflowWelcomeTitle ${LANG_KOREAN} "negaflow for Windows"
LangString NegaflowWelcomeText  ${LANG_KOREAN} "스캔한 필름이나 카메라로 복사한 필름을 가져와 베이스를 재고, 반전하고, 현상합니다. 컬러와 흑백, 네거티브와 포지티브를 모두 다룹니다. 원본 파일은 고쳐 쓰지 않습니다.$\r$\n$\r$\nnegaflow 에 필요한 것은 이 설치 파일에 전부 들어 있고, 사용자 폴더에만 씁니다.$\r$\n$\r$\n스캐너 조작은 별도의 스캐너 플러그인을 설치하면 나타납니다."
LangString NegaflowFinishTitle  ${LANG_KOREAN} "negaflow 준비 완료"
LangString NegaflowFinishText   ${LANG_KOREAN} "시작 메뉴에서 열 수 있습니다.$\r$\n$\r$\n스캐너를 쓰려면 negaflow-scanner-sane 도 설치하십시오."
LangString NegaflowFinishRun    ${LANG_KOREAN} "negaflow 열기"
LangString NegaflowFinishStar   ${LANG_KOREAN} "GitHub 에서 negaflow 에 별 남기기"
LangString NegaflowUninstallLink ${LANG_KOREAN} "negaflow 제거"
LangString NegaflowNeedsWindows ${LANG_KOREAN} "negaflow 는 Windows 11 빌드 ${MIN_OS_BUILD} 이상이 필요합니다.$\r$\n$\r$\n아무것도 설치하지 않았습니다. 이 PC 의 빌드:"
LangString NegaflowRegisterFailed ${LANG_KOREAN} "negaflow 가 앱 패키지를 등록하지 못했습니다.$\r$\n$\r$\n오류와, 전문이 남아 있는 파일입니다:"

LangString NegaflowWelcomeTitle ${LANG_JAPANESE} "negaflow for Windows"
LangString NegaflowWelcomeText  ${LANG_JAPANESE} "スキャンしたフィルムやカメラで複写したフィルムを読み込み、ベースを測り、反転して現像します。カラーとモノクロ、ネガとポジのどちらにも対応します。元のファイルは書き換えません。$\r$\n$\r$\n必要なものはこのインストーラーに揃っており、ユーザーフォルダーだけに書き込みます。$\r$\n$\r$\nスキャナーの操作は、別のスキャナープラグインを入れると現れます。"
LangString NegaflowFinishTitle  ${LANG_JAPANESE} "negaflow の準備ができました"
LangString NegaflowFinishText   ${LANG_JAPANESE} "スタートメニューから開けます。$\r$\n$\r$\nスキャナーを使うには negaflow-scanner-sane も入れてください。"
LangString NegaflowFinishRun    ${LANG_JAPANESE} "negaflow を開く"
LangString NegaflowFinishStar   ${LANG_JAPANESE} "GitHub で negaflow にスターを付ける"
LangString NegaflowUninstallLink ${LANG_JAPANESE} "negaflow のアンインストール"
LangString NegaflowNeedsWindows ${LANG_JAPANESE} "negaflow には Windows 11 ビルド ${MIN_OS_BUILD} 以降が必要です。$\r$\n$\r$\n何もインストールしていません。この PC のビルド:"
LangString NegaflowRegisterFailed ${LANG_JAPANESE} "negaflow がアプリパッケージを登録できませんでした。$\r$\n$\r$\nエラーと、全文が残っているファイルです:"

LangString NegaflowWelcomeTitle ${LANG_SIMPCHINESE} "negaflow for Windows"
LangString NegaflowWelcomeText  ${LANG_SIMPCHINESE} "导入扫描的胶片或用相机翻拍的胶片，测量片基、反转并进行显影。彩色与黑白、负片与正片均可处理。原始文件不会被改写。$\r$\n$\r$\nnegaflow 所需的一切都包含在此安装程序中，且只写入你的用户目录。$\r$\n$\r$\n安装单独的扫描仪插件后，扫描仪控件才会出现。"
LangString NegaflowFinishTitle  ${LANG_SIMPCHINESE} "negaflow 已就绪"
LangString NegaflowFinishText   ${LANG_SIMPCHINESE} "可从开始菜单打开。$\r$\n$\r$\n若要使用扫描仪，请一并安装 negaflow-scanner-sane。"
LangString NegaflowFinishRun    ${LANG_SIMPCHINESE} "打开 negaflow"
LangString NegaflowFinishStar   ${LANG_SIMPCHINESE} "在 GitHub 上为 negaflow 点星"
LangString NegaflowUninstallLink ${LANG_SIMPCHINESE} "卸载 negaflow"
LangString NegaflowNeedsWindows ${LANG_SIMPCHINESE} "negaflow 需要 Windows 11 版本 ${MIN_OS_BUILD} 或更高。$\r$\n$\r$\n尚未安装任何内容。此电脑的版本："
LangString NegaflowRegisterFailed ${LANG_SIMPCHINESE} "negaflow 无法注册其应用包。$\r$\n$\r$\n以下是错误，以及保存完整记录的文件："

LangString NegaflowWelcomeTitle ${LANG_FRENCH} "negaflow pour Windows"
LangString NegaflowWelcomeText  ${LANG_FRENCH} "Importez un scan ou une reproduction au boîtier, mesurez la base du film, inversez-la et développez. Couleur et noir et blanc, négatif et positif. Votre fichier d'origine n'est jamais réécrit.$\r$\n$\r$\nTout ce dont negaflow a besoin se trouve dans ce programme d'installation, qui n'écrit que dans votre profil utilisateur.$\r$\n$\r$\nLes commandes du scanner apparaissent une fois le module scanner installé séparément."
LangString NegaflowFinishTitle  ${LANG_FRENCH} "negaflow est prêt"
LangString NegaflowFinishText   ${LANG_FRENCH} "Vous le trouverez dans le menu Démarrer.$\r$\n$\r$\nPour utiliser un scanner, installez également negaflow-scanner-sane."
LangString NegaflowFinishRun    ${LANG_FRENCH} "Ouvrir negaflow"
LangString NegaflowFinishStar   ${LANG_FRENCH} "Mettre une étoile à negaflow sur GitHub"
LangString NegaflowUninstallLink ${LANG_FRENCH} "Désinstaller negaflow"
LangString NegaflowNeedsWindows ${LANG_FRENCH} "negaflow nécessite Windows 11 build ${MIN_OS_BUILD} ou plus récent.$\r$\n$\r$\nRien n'a été installé. Build de ce PC :"
LangString NegaflowRegisterFailed ${LANG_FRENCH} "negaflow n'a pas pu enregistrer son package d'application.$\r$\n$\r$\nL'erreur, et le fichier qui conserve le relevé complet :"

LangString NegaflowWelcomeTitle ${LANG_GERMAN} "negaflow für Windows"
LangString NegaflowWelcomeText  ${LANG_GERMAN} "Scan oder Kamera-Reproduktion importieren, die Filmbasis messen, invertieren und entwickeln. Farbe und Schwarzweiß, Negativ und Positiv. Ihre Originaldatei wird nie überschrieben.$\r$\n$\r$\nAlles, was negaflow braucht, steckt in diesem Installationsprogramm, und es schreibt ausschließlich in Ihr Benutzerprofil.$\r$\n$\r$\nScanner-Bedienelemente erscheinen, sobald das separate Scanner-Plug-in installiert ist."
LangString NegaflowFinishTitle  ${LANG_GERMAN} "negaflow ist bereit"
LangString NegaflowFinishText   ${LANG_GERMAN} "Sie finden es im Startmenü.$\r$\n$\r$\nFür einen Scanner installieren Sie zusätzlich negaflow-scanner-sane."
LangString NegaflowFinishRun    ${LANG_GERMAN} "negaflow öffnen"
LangString NegaflowFinishStar   ${LANG_GERMAN} "negaflow auf GitHub mit einem Stern versehen"
LangString NegaflowUninstallLink ${LANG_GERMAN} "negaflow deinstallieren"
LangString NegaflowNeedsWindows ${LANG_GERMAN} "negaflow benötigt Windows 11 Build ${MIN_OS_BUILD} oder neuer.$\r$\n$\r$\nEs wurde nichts installiert. Build dieses PCs:"
LangString NegaflowRegisterFailed ${LANG_GERMAN} "negaflow konnte sein Anwendungspaket nicht registrieren.$\r$\n$\r$\nDer Fehler und die Datei mit dem vollständigen Protokoll:"

LangString NegaflowUninstallWelcomeTitle ${LANG_ENGLISH} "Remove negaflow"
LangString NegaflowUninstallWelcomeText ${LANG_ENGLISH} "This removes negaflow from your user profile: the application folder, its package registration, and the Start-menu shortcut.$\r$\n$\r$\nYour photos, libraries, and settings are not touched, and the scanner plug-in negaflow-scanner-sane is removed separately."
LangString NegaflowUninstallFinishTitle ${LANG_ENGLISH} "negaflow has been removed"
LangString NegaflowUninstallFinishText ${LANG_ENGLISH} "The application folder and its package registration are gone.$\r$\n$\r$\nYour photos and libraries stayed where they were. To remove scanner support as well, uninstall negaflow-scanner-sane."
LangString NegaflowUnregisterFailed ${LANG_ENGLISH} "negaflow's package registration could not be removed.$\r$\n$\r$\nThe error, and the file that keeps the full record:"
LangString NegaflowUninstallBlocked ${LANG_ENGLISH} "negaflow's application folder could not be moved aside, so it was left in place.$\r$\n$\r$\nThe Windows error, the folder, and the file that keeps the full record:"
LangString NegaflowRuntimeFailed ${LANG_ENGLISH} "The Windows App Runtime could not be installed, so negaflow was not installed either.$\r$\n$\r$\nThe error, and the file that keeps the full record:"
LangString NegaflowReplaceBlocked ${LANG_ENGLISH} "The negaflow already installed here could not be moved aside, so nothing was changed.$\r$\n$\r$\nThe Windows error, the folder, and the file that keeps the full record:"
LangString NegaflowBadInstallDir ${LANG_ENGLISH} "negaflow cannot be installed in the root of a drive.$\r$\n$\r$\nUninstalling removes its folder entirely, so negaflow needs a folder of its own. Pick a subfolder instead:"
LangString NegaflowDirNotEmpty ${LANG_ENGLISH} "This folder already holds other files.$\r$\n$\r$\nUninstalling removes the folder entirely, so those files would go with it. Pick an empty folder, or one where negaflow is already installed:"

LangString NegaflowUninstallWelcomeTitle ${LANG_KOREAN} "negaflow 제거"
LangString NegaflowUninstallWelcomeText ${LANG_KOREAN} "사용자 폴더에 있는 negaflow 를 지웁니다 — 앱 폴더, 패키지 등록, 시작 메뉴 바로 가기입니다.$\r$\n$\r$\n사진과 라이브러리, 설정은 건드리지 않으며, 스캐너 플러그인 negaflow-scanner-sane 은 따로 제거합니다."
LangString NegaflowUninstallFinishTitle ${LANG_KOREAN} "negaflow 를 제거했습니다"
LangString NegaflowUninstallFinishText ${LANG_KOREAN} "앱 폴더와 패키지 등록을 지웠습니다.$\r$\n$\r$\n사진과 라이브러리는 그대로 있습니다. 스캐너 기능까지 지우려면 negaflow-scanner-sane 도 제거하십시오."
LangString NegaflowUnregisterFailed ${LANG_KOREAN} "negaflow 의 패키지 등록을 지우지 못했습니다.$\r$\n$\r$\n오류와, 전문이 남아 있는 파일입니다:"
LangString NegaflowUninstallBlocked ${LANG_KOREAN} "negaflow 앱 폴더를 옮기지 못해 그대로 두었습니다.$\r$\n$\r$\nWindows 오류 번호와 그 폴더, 그리고 전문이 남아 있는 파일입니다:"
LangString NegaflowRuntimeFailed ${LANG_KOREAN} "Windows App Runtime 을 설치하지 못해 negaflow 도 설치하지 않았습니다.$\r$\n$\r$\n오류와, 전문이 남아 있는 파일입니다:"
LangString NegaflowReplaceBlocked ${LANG_KOREAN} "여기 이미 있던 negaflow 를 옮기지 못해 아무것도 바꾸지 않았습니다.$\r$\n$\r$\nWindows 오류 번호와 그 폴더, 그리고 전문이 남아 있는 파일입니다:"
LangString NegaflowBadInstallDir ${LANG_KOREAN} "드라이브 루트에는 negaflow 를 설치할 수 없습니다.$\r$\n$\r$\n제거할 때 설치 폴더를 통째로 지우므로 negaflow 전용 폴더여야 합니다. 하위 폴더를 고르십시오:"
LangString NegaflowDirNotEmpty ${LANG_KOREAN} "이 폴더에는 다른 파일이 이미 들어 있습니다.$\r$\n$\r$\n제거할 때 폴더를 통째로 지우므로 그 파일들도 함께 사라집니다. 빈 폴더나, negaflow 가 이미 설치된 폴더를 고르십시오:"

LangString NegaflowUninstallWelcomeTitle ${LANG_JAPANESE} "negaflow のアンインストール"
LangString NegaflowUninstallWelcomeText ${LANG_JAPANESE} "ユーザーフォルダーの negaflow を削除します — アプリフォルダー、パッケージ登録、スタートメニューのショートカットです。$\r$\n$\r$\n写真・ライブラリ・設定には触れません。スキャナープラグイン negaflow-scanner-sane は別に削除します。"
LangString NegaflowUninstallFinishTitle ${LANG_JAPANESE} "negaflow を削除しました"
LangString NegaflowUninstallFinishText ${LANG_JAPANESE} "アプリフォルダーとパッケージ登録を削除しました。$\r$\n$\r$\n写真とライブラリはそのままです。スキャナー機能も消すには negaflow-scanner-sane も削除してください。"
LangString NegaflowUnregisterFailed ${LANG_JAPANESE} "negaflow のパッケージ登録を削除できませんでした。$\r$\n$\r$\nエラーと、全文が残っているファイルです:"
LangString NegaflowUninstallBlocked ${LANG_JAPANESE} "negaflow のアプリフォルダーを移動できず、そのまま残しました。$\r$\n$\r$\nWindows のエラー番号とそのフォルダー、そして全文が残っているファイルです:"
LangString NegaflowRuntimeFailed ${LANG_JAPANESE} "Windows App Runtime をインストールできず、negaflow もインストールしませんでした。$\r$\n$\r$\nエラーと、全文が残っているファイルです:"
LangString NegaflowReplaceBlocked ${LANG_JAPANESE} "ここにあった negaflow を移動できず、何も変更しませんでした。$\r$\n$\r$\nWindows のエラー番号とそのフォルダー、そして全文が残っているファイルです:"
LangString NegaflowBadInstallDir ${LANG_JAPANESE} "ドライブ直下には negaflow をインストールできません。$\r$\n$\r$\nアンインストール時にそのフォルダーを丸ごと削除するため、negaflow 専用のフォルダーが必要です。サブフォルダーを選んでください:"
LangString NegaflowDirNotEmpty ${LANG_JAPANESE} "このフォルダーには既に他のファイルがあります。$\r$\n$\r$\nアンインストール時にフォルダーを丸ごと削除するため、それらも一緒に消えます。空のフォルダーか、negaflow が既に入っているフォルダーを選んでください:"

LangString NegaflowUninstallWelcomeTitle ${LANG_SIMPCHINESE} "卸载 negaflow"
LangString NegaflowUninstallWelcomeText ${LANG_SIMPCHINESE} "将从你的用户目录中删除 negaflow：应用文件夹、包注册和开始菜单快捷方式。$\r$\n$\r$\n照片、图库和设置不会被改动，扫描仪插件 negaflow-scanner-sane 需另行卸载。"
LangString NegaflowUninstallFinishTitle ${LANG_SIMPCHINESE} "negaflow 已卸载"
LangString NegaflowUninstallFinishText ${LANG_SIMPCHINESE} "应用文件夹和包注册已删除。$\r$\n$\r$\n照片和图库仍在原处。若要一并移除扫描仪功能，请卸载 negaflow-scanner-sane。"
LangString NegaflowUnregisterFailed ${LANG_SIMPCHINESE} "无法删除 negaflow 的包注册。$\r$\n$\r$\n以下是错误，以及保存完整记录的文件："
LangString NegaflowUninstallBlocked ${LANG_SIMPCHINESE} "无法移走 negaflow 的应用文件夹，已原样保留。$\r$\n$\r$\n以下是 Windows 错误号、该文件夹，以及保存完整记录的文件："
LangString NegaflowRuntimeFailed ${LANG_SIMPCHINESE} "无法安装 Windows App Runtime，因此也未安装 negaflow。$\r$\n$\r$\n以下是错误，以及保存完整记录的文件："
LangString NegaflowReplaceBlocked ${LANG_SIMPCHINESE} "无法移走此处已有的 negaflow，未做任何更改。$\r$\n$\r$\n以下是 Windows 错误号、该文件夹，以及保存完整记录的文件："
LangString NegaflowBadInstallDir ${LANG_SIMPCHINESE} "不能把 negaflow 安装在驱动器根目录。$\r$\n$\r$\n卸载时会整个删除安装文件夹，因此 negaflow 需要独立的文件夹。请选择一个子文件夹："
LangString NegaflowDirNotEmpty ${LANG_SIMPCHINESE} "此文件夹中已有其他文件。$\r$\n$\r$\n卸载时会整个删除该文件夹，那些文件也会一并消失。请选择空文件夹，或已安装 negaflow 的文件夹："

LangString NegaflowUninstallWelcomeTitle ${LANG_FRENCH} "Désinstaller negaflow"
LangString NegaflowUninstallWelcomeText ${LANG_FRENCH} "Ceci supprime negaflow de votre profil utilisateur : le dossier de l'application, son enregistrement de package et le raccourci du menu Démarrer.$\r$\n$\r$\nVos photos, bibliothèques et réglages ne sont pas touchés ; le module scanner negaflow-scanner-sane se désinstalle séparément."
LangString NegaflowUninstallFinishTitle ${LANG_FRENCH} "negaflow a été désinstallé"
LangString NegaflowUninstallFinishText ${LANG_FRENCH} "Le dossier de l'application et son enregistrement de package ont disparu.$\r$\n$\r$\nVos photos et bibliothèques sont restées en place. Pour retirer aussi la prise en charge du scanner, désinstallez negaflow-scanner-sane."
LangString NegaflowUnregisterFailed ${LANG_FRENCH} "L'enregistrement du package de negaflow n'a pas pu être supprimé.$\r$\n$\r$\nL'erreur, et le fichier qui conserve le relevé complet :"
LangString NegaflowUninstallBlocked ${LANG_FRENCH} "Le dossier d'application de negaflow n'a pas pu être déplacé ; il a été laissé en place.$\r$\n$\r$\nL'erreur Windows, le dossier, et le fichier qui conserve le relevé complet :"
LangString NegaflowRuntimeFailed ${LANG_FRENCH} "Le Windows App Runtime n'a pas pu être installé, donc negaflow ne l'a pas été non plus.$\r$\n$\r$\nL'erreur, et le fichier qui conserve le relevé complet :"
LangString NegaflowReplaceBlocked ${LANG_FRENCH} "Le negaflow déjà présent ici n'a pas pu être déplacé ; rien n'a été modifié.$\r$\n$\r$\nL'erreur Windows, le dossier, et le fichier qui conserve le relevé complet :"
LangString NegaflowBadInstallDir ${LANG_FRENCH} "negaflow ne peut pas être installé à la racine d'un disque.$\r$\n$\r$\nLa désinstallation supprime entièrement son dossier ; negaflow a donc besoin d'un dossier à lui. Choisissez un sous-dossier :"
LangString NegaflowDirNotEmpty ${LANG_FRENCH} "Ce dossier contient déjà d'autres fichiers.$\r$\n$\r$\nLa désinstallation supprime le dossier entier, ces fichiers partiraient avec lui. Choisissez un dossier vide, ou un dossier où negaflow est déjà installé :"

LangString NegaflowUninstallWelcomeTitle ${LANG_GERMAN} "negaflow entfernen"
LangString NegaflowUninstallWelcomeText ${LANG_GERMAN} "Damit wird negaflow aus Ihrem Benutzerprofil entfernt: der Anwendungsordner, seine Paketregistrierung und die Startmenü-Verknüpfung.$\r$\n$\r$\nIhre Fotos, Bibliotheken und Einstellungen bleiben unberührt; das Scanner-Plug-in negaflow-scanner-sane wird separat entfernt."
LangString NegaflowUninstallFinishTitle ${LANG_GERMAN} "negaflow wurde entfernt"
LangString NegaflowUninstallFinishText ${LANG_GERMAN} "Anwendungsordner und Paketregistrierung sind entfernt.$\r$\n$\r$\nIhre Fotos und Bibliotheken sind geblieben. Um auch die Scanner-Unterstützung zu entfernen, deinstallieren Sie negaflow-scanner-sane."
LangString NegaflowUnregisterFailed ${LANG_GERMAN} "Die Paketregistrierung von negaflow konnte nicht entfernt werden.$\r$\n$\r$\nDer Fehler und die Datei mit dem vollständigen Protokoll:"
LangString NegaflowUninstallBlocked ${LANG_GERMAN} "Der Anwendungsordner von negaflow konnte nicht verschoben werden und blieb an Ort und Stelle.$\r$\n$\r$\nDer Windows-Fehler, der Ordner und die Datei mit dem vollständigen Protokoll:"
LangString NegaflowRuntimeFailed ${LANG_GERMAN} "Die Windows App Runtime konnte nicht installiert werden, daher wurde auch negaflow nicht installiert.$\r$\n$\r$\nDer Fehler und die Datei mit dem vollständigen Protokoll:"
LangString NegaflowReplaceBlocked ${LANG_GERMAN} "Das hier bereits vorhandene negaflow konnte nicht verschoben werden; es wurde nichts geändert.$\r$\n$\r$\nDer Windows-Fehler, der Ordner und die Datei mit dem vollständigen Protokoll:"
LangString NegaflowBadInstallDir ${LANG_GERMAN} "negaflow kann nicht im Stammverzeichnis eines Laufwerks installiert werden.$\r$\n$\r$\nBeim Deinstallieren wird der Ordner vollständig entfernt, negaflow braucht daher einen eigenen Ordner. Wählen Sie einen Unterordner:"
LangString NegaflowDirNotEmpty ${LANG_GERMAN} "Dieser Ordner enthält bereits andere Dateien.$\r$\n$\r$\nBeim Deinstallieren wird der Ordner vollständig entfernt, diese Dateien gingen mit verloren. Wählen Sie einen leeren Ordner oder einen, in dem negaflow bereits installiert ist:"

Function OpenProjectPage
  ExecShell "open" "https://github.com/habinsong/negaflow"
FunctionEnd

/*
설치 위치가 안전한지 봅니다.

**제거는 `$INSTDIR` 을 통째로 지웁니다**(`Rename` 뒤 `RMDir /r`). 그런데 위치 화면은 아무
폴더나 받고 있었습니다 — 사용자가 `D:\사진` 을 고르면 설치는 되고, 그 다음 제거가 그 사진을
전부 지웁니다. 설치 쪽도 마찬가지로 기존 내용을 `.previous` 로 옮겼다가 지웁니다.

그래서 셋만 받습니다: 없는 폴더 · 빈 폴더 · 이미 negaflow 가 들어 있는 폴더.
드라이브 루트는 이름을 바꿀 수도 없으므로(`D:\` -> `D:\.previous` 가 성립하지 않습니다)
따로 막습니다.
*/
Function VerifyInstallDirectory
  ; 루트 판정은 **부모가 있는지**로 합니다. 마지막 글자가 `\` 인지 보면 `D:\` 는 걸리지만
  ; `D:` 는 빠져나갑니다 - `/D=` 로 넘어오는 값에는 둘 다 옵니다. 실측: `${GetParent}` 는
  ; `D:\` 와 `D:` 에 모두 빈 값을, `D:\Negaflow` 에는 `D:` 를 돌려줍니다.
  ${GetParent} "$INSTDIR" $R0
  ${If} $R0 == ""
    MessageBox MB_ICONSTOP "$(NegaflowBadInstallDir)$\r$\n$\r$\n$INSTDIR" /SD IDOK
    Abort
  ${EndIf}
  ${IfNot} ${FileExists} "$INSTDIR\*.*"
    Return
  ${EndIf}
  ; 이미 negaflow 가 사는 폴더면 덮어쓰기(업그레이드)입니다. 그 자리는 원래 우리 것입니다.
  ${If} ${FileExists} "$INSTDIR\AppxManifest.xml"
  ${OrIf} ${FileExists} "$INSTDIR\uninstall.exe"
    Return
  ${EndIf}
  ; 남은 경우는 "이미 있는 폴더". 비어 있어야만 받습니다.
  FindFirst $R1 $R2 "$INSTDIR\*.*"
  negaflow_dir_scan:
  StrCmp $R2 "" negaflow_dir_empty
  StrCmp $R2 "." negaflow_dir_next
  StrCmp $R2 ".." negaflow_dir_next
  FindClose $R1
  MessageBox MB_ICONSTOP "$(NegaflowDirNotEmpty)$\r$\n$\r$\n$INSTDIR" /SD IDOK
  Abort
  negaflow_dir_next:
  FindNext $R1 $R2
  Goto negaflow_dir_scan
  negaflow_dir_empty:
  FindClose $R1
FunctionEnd

Function .onInit
  !insertmacro MUI_LANGDLL_DISPLAY

  ; 등록이 거부될 기계는 **파일을 하나도 건드리기 전에** 돌려보냅니다. 이 확인이 없어서
  ; 최소 빌드에 못 미치는 기계도 설치를 끝까지 진행했고, 마지막 등록에서 실패한 뒤 그
  ; 자리에서 앱 폴더를 지웠습니다 - 있던 negaflow 까지 사라졌습니다.
  ;
  ; `GetVersion` 은 실행 파일 매니페스트에 따라 낮은 값을 돌려주므로, OS 가 스스로 적어 둔
  ; 빌드 번호를 읽습니다. NSIS 는 32 비트라 리디렉션을 끄고 64 비트 하이브를 봐야 합니다.
  ; 읽지 못하면 막지 않습니다 - 빌드를 확인하지 못한 것이 설치를 거절할 이유는 아닙니다.
  SetRegView 64
  ReadRegStr $0 HKLM "Software\Microsoft\Windows NT\CurrentVersion" "CurrentBuildNumber"
  SetRegView lastused
  ${If} $0 != ""
  ${AndIf} $0 < ${MIN_OS_BUILD}
    MessageBox MB_ICONSTOP "$(NegaflowNeedsWindows) 10.0.$0" /SD IDOK
    Abort
  ${EndIf}
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

; Win32 오류 **번호를 이름으로** 바꿉니다.
;
; 번호만 보여 주면 사용자도 QA 도 그것을 따로 찾아봐야 하고, 우리가 목록을 지어 넣으면
; 번호가 늘 때마다 어긋나는 데다 여섯 언어 번역까지 우리 몫이 됩니다. Windows 가 이미
; 가지고 있는 문장을 그대로 씁니다 - 사용자의 언어로 나옵니다. 모르는 번호면 번호만
; 남습니다(실측: 999999 -> "Windows 999999").
!macro Win32Message code out
  StrCpy $R8 ""
  ; 0x1200 = FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS
  System::Call 'kernel32::FormatMessageW(i 0x1200, p 0, i ${code}, i 0, t .R8, i ${NSIS_MAX_STRLEN}, p 0) i .R7'
  ${TrimNewLines} $R8 $R8
  ${If} $R8 == ""
    StrCpy ${out} "Windows ${code}"
  ${Else}
    StrCpy ${out} "Windows ${code}: $R8"
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
  ; 중간에 끊긴 **제거**가 남긴 자리입니다. 그대로 두면 다음 제거가 `.removing` 을 만들지
  ; 못해 183(파일이 이미 있음)으로 영영 실패합니다. 설치할 때도 함께 치웁니다.
  RMDir /r "$INSTDIR.removing"

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
    ; 여기도 "Windows 업데이트를 마치라" 는 한 문장뿐이었습니다. 무엇이 거부했는지는
    ; `$1` 에 들려 있으면서 화면에는 나가지 않았습니다.
    StrCpy $2 $1 1000
    MessageBox MB_ICONSTOP "$(NegaflowRuntimeFailed)$\r$\n$\r$\n$2$\r$\n$\r$\n$RegisterLog" /SD IDOK
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
    ; **바로 위에서 등록을 푼 참입니다.** 제거 섹션은 그 뒤 배포 서비스가 폴더를 놓을
    ; 때까지 30 초를 기다리는데, 여기는 한 번만 시도하고 "실행 중인 Negaflow 를 닫으라" 고
    ; 말했습니다 — 같은 경합인데 한쪽만 기다리고 있었습니다. 같은 자리를 둡니다.
    ; 실패하면 이유(Win32 번호)도 그대로 내보냅니다. 번호의 뜻은 제거 섹션 주석에 있습니다.
    StrCpy $2 0
    negaflow_install_moveaside:
    System::Call 'kernel32::MoveFileW(w "$INSTDIR", w "$Backup") i .r3 ?e'
    Pop $4
    ${If} $3 <> 0
      Goto negaflow_install_moved
    ${EndIf}
    IntOp $2 $2 + 1
    ${If} $2 < 60
      Sleep 500
      Goto negaflow_install_moveaside
    ${EndIf}
    RMDir /r "$Staging"
    !insertmacro Win32Message $4 $5
    !insertmacro LogValue "move-aside-failed" $5
    MessageBox MB_ICONSTOP "$(NegaflowReplaceBlocked)$\r$\n$\r$\n$5$\r$\n$INSTDIR$\r$\n$\r$\n$RegisterLog" /SD IDOK
    Abort "Move aside failed: $5"
    negaflow_install_moved:
    !insertmacro LogValue "move-aside-attempts" $2
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
    ; 이 자리는 원인을 가리지 않고 언제나 "개발자 모드" 를 탓했습니다. 개발자 모드가 켜진
    ; 기계에서도 같은 문구가 떠서, QA 는 이미 맞는 자리를 두 번 확인했고 진짜 원인은
    ; 로그에만 남았습니다(2026-08-31). 들고 있는 오류와 기록 위치를 그대로 보여 줍니다.
    ; 출력이 길면 대화상자가 화면을 넘칩니다 - 전문은 로그에 있으므로 앞머리만 싣습니다.
    StrCpy $2 $1 1000
    MessageBox MB_ICONSTOP "$(NegaflowRegisterFailed)$\r$\n$\r$\n$2$\r$\n$\r$\n$RegisterLog" /SD IDOK
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
  ; **제거가 실패하면 아무것도 남지 않았습니다.** `$RegisterLog` 는 설치 섹션에서만 정해지고
  ; 이쪽은 쓰지 않아, QA 가 "제거가 안 된다" 고 하면 화면의 한 문장이 전부였습니다
  ; (2026-08-31). 설치 쪽과 같은 방식으로 파일에 남깁니다 - 이름만 갈라 서로 덮지 않습니다.
  StrCpy $RegisterLog "$TEMP\negaflow-uninstall.log"
  Delete "$RegisterLog"
  !insertmacro LogValue "install-dir" "$INSTDIR"

  nsExec::ExecToStack '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$INSTDIR\package-registration.ps1" -Action Unregister'
  Pop $0
  Pop $1
  !insertmacro LogExec "unregister" $0 $1
  ${If} $0 != 0
    StrCpy $2 $1 1000
    MessageBox MB_ICONSTOP "$(NegaflowUnregisterFailed)$\r$\n$\r$\n$2$\r$\n$\r$\n$RegisterLog" /SD IDOK
    Abort "Package unregistration failed: $1"
  ${EndIf}

  ; 패키지 신원을 막 지운 참이라 **배포 서비스가 아직 이 폴더를 붙들고 있습니다.**
  ; 곧바로 옮기면 공유 위반으로 실패하고, 그러면 제거가 앱 폴더를 통째로 남긴 채
  ; 끝납니다 - 2026-08-27 로컬 CI 가 그렇게 실패했습니다. 손을 뗄 때까지 기다립니다.
  ; 30 초를 넘기면 그때는 정말로 Negaflow 가 떠 있는 것입니다.
  ; `Rename` 은 **실패했다는 것만** 알려 주고 이유는 알려 주지 않습니다. 재부팅 뒤 앱을
  ; 닫은 상태에서도 30 초 내내 실패한다는 보고가 있었는데(QA 2026-08-31), 그때 화면에 나간
  ; 문장은 "실행 중인 Negaflow 를 닫으십시오" 하나였습니다 — 잠금이 아니라 권한이거나
  ; 필터 드라이버일 수 있는데, 그 둘을 가릴 방법이 없었습니다.
  ;
  ; `MoveFileW` 를 직접 불러 Win32 오류 번호를 받습니다. 실측으로 확인한 것들입니다:
  ;   5   액세스 거부 - 폴더 **안의** 파일을 누가 배타적으로 열고 있어도 이 번호이고,
  ;       권한이나 보안 제품이 막아도 이 번호입니다. 둘을 이 번호만으로는 가르지 못합니다.
  ;   32  공유 위반
  ;   183 대상 이름이 이미 있음 - 바로 아래에서 치우므로 여기까지 오지 않아야 합니다.
  ;
  ; 지난 제거가 중간에 끊기면 `.removing` 이 남고, 그러면 그 다음 제거는 **언제나** 183 으로
  ; 실패합니다. 설치 섹션은 시작할 때 `$Staging`·`$Backup` 을 치우는데 이쪽엔 그 자리가
  ; 없었습니다. 같은 자리를 둡니다.
  RMDir /r "$INSTDIR.removing"
  StrCpy $2 0
  ; 앱 폴더가 **이미 없으면** 옮길 것이 없습니다. 손으로 지웠거나, 지난 제거가 여기까지는
  ; 끝냈거나입니다. 그 경우에 30 초를 기다렸다가 "실행 중인 negaflow 를 닫으라" 고 말하는
  ; 것은 거짓말이고, 시작 메뉴 항목과 레지스트리는 그대로 남습니다. 지나가서 마저 치웁니다.
  ${IfNot} ${FileExists} "$INSTDIR\*.*"
    !insertmacro LogValue "install-dir-already-gone" "1"
    Goto negaflow_uninstall_renamed
  ${EndIf}
  negaflow_uninstall_rename:
  System::Call 'kernel32::MoveFileW(w "$INSTDIR", w "$INSTDIR.removing") i .r3 ?e'
  Pop $4
  ${If} $3 <> 0
    Goto negaflow_uninstall_renamed
  ${EndIf}
  IntOp $2 $2 + 1
  ${If} $2 < 60
    Sleep 500
    Goto negaflow_uninstall_rename
  ${EndIf}
  !insertmacro Win32Message $4 $5
  !insertmacro LogValue "rename-failed" $5
  MessageBox MB_ICONSTOP "$(NegaflowUninstallBlocked)$\r$\n$\r$\n$5$\r$\n$INSTDIR$\r$\n$\r$\n$RegisterLog" /SD IDOK
  Abort "Uninstall rename failed: $5"
  negaflow_uninstall_renamed:
  !insertmacro LogValue "rename-attempts" $2

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
