import Chromabase

struct QuickStartHelpContent: Equatable {
    struct Step: Equatable, Identifiable {
        let id: Int
        let title: String
        let detail: String
        let systemImage: String
    }

    let title: String
    let introduction: String
    let steps: [Step]
    let versionLabel: String
    let shortcutNote: String

    static func localized(for language: AppLanguage) -> Self {
        switch language.resolved {
        case .korean:
            return content(
                title: "빠른 시작",
                introduction: "가져오기 또는 스캔부터 현상과 내보내기까지의 기본 흐름입니다.",
                importTitle: "1. 가져오기 또는 스캔",
                importDetail: "사진을 가져오거나 외부 스캐너 플러그인으로 스캔합니다. 원본 파일은 변경하지 않습니다.",
                developTitle: "2. 현상",
                developDetail: "MAIN과 수동 보정을 기본으로 색상과 톤을 조정합니다. 자동 보정은 직접 선택할 때만 적용됩니다.",
                exportTitle: "3. 내보내기",
                exportDetail: "대상 폴더와 형식을 확인한 뒤 비파괴 현상 결과를 새 파일로 내보냅니다.",
                versionLabel: "문서 버전",
                shortcutNote: "빠른 시작은 언제든지 Command-Shift-H로 열 수 있습니다."
            )
        case .japanese:
            return content(
                title: "クイックスタート",
                introduction: "読み込みまたはスキャンから現像、書き出しまでの基本手順です。",
                importTitle: "1. 読み込みまたはスキャン",
                importDetail: "写真を読み込むか、外部スキャナープラグインでスキャンします。元ファイルは変更されません。",
                developTitle: "2. 現像",
                developDetail: "MAINと手動補正を基本に色と階調を調整します。自動補正は明示的に選択した場合だけ適用されます。",
                exportTitle: "3. 書き出し",
                exportDetail: "保存先と形式を確認し、非破壊の現像結果を新しいファイルとして書き出します。",
                versionLabel: "ドキュメントバージョン",
                shortcutNote: "クイックスタートはCommand-Shift-Hでいつでも開けます。"
            )
        case .simplifiedChinese:
            return content(
                title: "快速入门",
                introduction: "从导入或扫描到显影和导出的基本流程。",
                importTitle: "1. 导入或扫描",
                importDetail: "导入照片，或通过外部扫描仪插件进行扫描。原始文件不会被修改。",
                developTitle: "2. 显影",
                developDetail: "默认使用MAIN和手动调整来处理颜色与影调。自动调整仅在明确选择时应用。",
                exportTitle: "3. 导出",
                exportDetail: "确认目标文件夹和格式后，将非破坏性显影结果导出为新文件。",
                versionLabel: "文档版本",
                shortcutNote: "随时按Command-Shift-H打开快速入门。"
            )
        case .french:
            return content(
                title: "Démarrage rapide",
                introduction: "Le flux essentiel, de l’importation ou la numérisation au développement et à l’exportation.",
                importTitle: "1. Importer ou numériser",
                importDetail: "Importez des photos ou numérisez avec un module externe de scanner. Les fichiers source restent inchangés.",
                developTitle: "2. Développer",
                developDetail: "Réglez la couleur et la tonalité avec MAIN et les réglages manuels par défaut. Les réglages automatiques restent optionnels.",
                exportTitle: "3. Exporter",
                exportDetail: "Vérifiez le dossier et le format, puis exportez le résultat non destructif dans un nouveau fichier.",
                versionLabel: "Version de la documentation",
                shortcutNote: "Ouvrez ce démarrage rapide à tout moment avec Command-Shift-H."
            )
        case .german:
            return content(
                title: "Schnellstart",
                introduction: "Der grundlegende Ablauf vom Import oder Scan über die Entwicklung bis zum Export.",
                importTitle: "1. Importieren oder scannen",
                importDetail: "Importieren Sie Fotos oder scannen Sie mit einem externen Scanner-Plugin. Quelldateien bleiben unverändert.",
                developTitle: "2. Entwickeln",
                developDetail: "Passen Sie Farbe und Ton standardmäßig mit MAIN und manuellen Reglern an. Automatik wird nur ausdrücklich angewendet.",
                exportTitle: "3. Exportieren",
                exportDetail: "Prüfen Sie Zielordner und Format und exportieren Sie das nichtdestruktive Ergebnis als neue Datei.",
                versionLabel: "Dokumentationsversion",
                shortcutNote: "Öffnen Sie den Schnellstart jederzeit mit Command-Shift-H."
            )
        case .system, .english:
            return content(
                title: "Quick Start",
                introduction: "The essential flow from import or scan through develop and export.",
                importTitle: "1. Import or Scan",
                importDetail: "Import photos or scan through an external scanner plugin. Source files remain unchanged.",
                developTitle: "2. Develop",
                developDetail: "Adjust color and tone with MAIN and manual controls by default. Automatic adjustments remain opt-in.",
                exportTitle: "3. Export",
                exportDetail: "Confirm the destination and format, then export the non-destructive result as a new file.",
                versionLabel: "Documentation version",
                shortcutNote: "Open Quick Start at any time with Command-Shift-H."
            )
        }
    }

    private static func content(
        title: String,
        introduction: String,
        importTitle: String,
        importDetail: String,
        developTitle: String,
        developDetail: String,
        exportTitle: String,
        exportDetail: String,
        versionLabel: String,
        shortcutNote: String
    ) -> Self {
        Self(
            title: title,
            introduction: introduction,
            steps: [
                Step(id: 1, title: importTitle, detail: importDetail, systemImage: "square.and.arrow.down"),
                Step(id: 2, title: developTitle, detail: developDetail, systemImage: "slider.horizontal.3"),
                Step(id: 3, title: exportTitle, detail: exportDetail, systemImage: "square.and.arrow.up")
            ],
            versionLabel: versionLabel,
            shortcutNote: shortcutNote
        )
    }
}

struct QuickStartHelpDocument: Equatable {
    let content: QuickStartHelpContent
    let version: String

    static func current(for language: AppLanguage) -> Self {
        Self(
            content: .localized(for: language),
            version: NegaflowProductVersion.applicationVersion()
        )
    }
}
