import Foundation

enum LibraryRecoveryLocalizedText: CaseIterable {
    case title
    case retry
    case revealInFinder
    case copyDiagnostics
    case noBackupsHint
    case selectBackupHint
    case unusableBackupHint
    case startFresh
    case startFreshConfirmationTitle
    case startFreshConfirmationMessage
    case startFreshFailed
}

extension AppLocalization {
    static func libraryRecoveryText(
        _ key: LibraryRecoveryLocalizedText,
        language: AppLanguage
    ) -> String {
        switch language.resolved {
        case .english:
            switch key {
            case .title: "Library Recovery"
            case .retry: "Retry"
            case .revealInFinder: "Show in Finder"
            case .copyDiagnostics: "Copy Diagnostics"
            case .noBackupsHint: "No catalog backups yet. If you have a backup elsewhere, put its folder in the backup directory and press Refresh; otherwise start a new library — your photo files are never touched."
            case .selectBackupHint: "Select a backup to restore."
            case .unusableBackupHint: "This backup cannot be read and cannot be restored."
            case .startFresh: "Start New Library"
            case .startFreshConfirmationTitle: "Start a new library?"
            case .startFreshConfirmationMessage: "The current catalog is set aside next to it, not deleted, and your photo files and backups stay where they are. The library list starts empty."
            case .startFreshFailed: "Could not start a new library."
            }
        case .korean:
            switch key {
            case .title: "라이브러리 복구"
            case .retry: "재시도"
            case .revealInFinder: "Finder에서 보기"
            case .copyDiagnostics: "진단 복사"
            case .noBackupsHint: "아직 카탈로그 백업이 없습니다. 다른 곳에 백업이 있으면 백업 폴더에 넣고 새로 고침을 누르세요. 없으면 새 라이브러리로 시작하면 됩니다 — 사진 파일은 건드리지 않습니다."
            case .selectBackupHint: "복원할 백업을 먼저 고르세요."
            case .unusableBackupHint: "이 백업은 읽을 수 없어 복원할 수 없습니다."
            case .startFresh: "새 라이브러리로 시작"
            case .startFreshConfirmationTitle: "새 라이브러리로 시작할까요?"
            case .startFreshConfirmationMessage: "지금 카탈로그는 지우지 않고 옆에 보관합니다. 사진 파일과 백업은 그대로 두고, 라이브러리 목록만 빈 채로 시작합니다."
            case .startFreshFailed: "새 라이브러리를 시작하지 못했습니다."
            }
        case .japanese:
            switch key {
            case .title: "ライブラリの復旧"
            case .retry: "再試行"
            case .revealInFinder: "Finderで表示"
            case .copyDiagnostics: "診断情報をコピー"
            case .noBackupsHint: "カタログのバックアップがまだありません。別の場所にバックアップがあれば、そのフォルダをバックアップ先に置いて更新してください。なければ新しいライブラリで始められます — 写真ファイルには触れません。"
            case .selectBackupHint: "復元するバックアップを選んでください。"
            case .unusableBackupHint: "このバックアップは読み込めないため復元できません。"
            case .startFresh: "新しいライブラリで開始"
            case .startFreshConfirmationTitle: "新しいライブラリで開始しますか？"
            case .startFreshConfirmationMessage: "現在のカタログは削除せず隣に保管します。写真ファイルとバックアップはそのままで、ライブラリの一覧だけが空の状態で始まります。"
            case .startFreshFailed: "新しいライブラリを開始できませんでした。"
            }
        case .simplifiedChinese:
            switch key {
            case .title: "图库恢复"
            case .retry: "重试"
            case .revealInFinder: "在 Finder 中显示"
            case .copyDiagnostics: "拷贝诊断信息"
            case .noBackupsHint: "尚无图库目录备份。如果备份在别处，请将其文件夹放入备份目录后点按刷新；否则可以新建图库 — 照片文件不会被改动。"
            case .selectBackupHint: "请先选择要恢复的备份。"
            case .unusableBackupHint: "此备份无法读取，因此无法恢复。"
            case .startFresh: "新建图库"
            case .startFreshConfirmationTitle: "要新建图库吗？"
            case .startFreshConfirmationMessage: "当前目录不会删除，会保留在原处旁边。照片文件和备份保持不变，只有图库列表从空白开始。"
            case .startFreshFailed: "无法新建图库。"
            }
        case .french:
            switch key {
            case .title: "Récupération de la bibliothèque"
            case .retry: "Réessayer"
            case .revealInFinder: "Afficher dans le Finder"
            case .copyDiagnostics: "Copier le diagnostic"
            case .noBackupsHint: "Aucune sauvegarde du catalogue pour l’instant. Si vous en avez une ailleurs, placez son dossier dans le répertoire de sauvegarde puis actualisez ; sinon, démarrez une nouvelle bibliothèque — vos fichiers photo ne sont jamais touchés."
            case .selectBackupHint: "Sélectionnez d’abord une sauvegarde à restaurer."
            case .unusableBackupHint: "Cette sauvegarde est illisible et ne peut pas être restaurée."
            case .startFresh: "Nouvelle bibliothèque"
            case .startFreshConfirmationTitle: "Démarrer une nouvelle bibliothèque ?"
            case .startFreshConfirmationMessage: "Le catalogue actuel est mis de côté à proximité, pas supprimé. Vos fichiers photo et vos sauvegardes restent en place ; seule la liste de la bibliothèque démarre vide."
            case .startFreshFailed: "Impossible de démarrer une nouvelle bibliothèque."
            }
        case .german:
            switch key {
            case .title: "Mediathek wiederherstellen"
            case .retry: "Erneut versuchen"
            case .revealInFinder: "Im Finder anzeigen"
            case .copyDiagnostics: "Diagnose kopieren"
            case .noBackupsHint: "Noch keine Katalogsicherungen. Wenn Sie anderswo eine Sicherung haben, legen Sie deren Ordner in das Sicherungsverzeichnis und aktualisieren Sie; andernfalls beginnen Sie eine neue Mediathek — Ihre Fotodateien bleiben unberührt."
            case .selectBackupHint: "Wählen Sie zuerst eine Sicherung zum Wiederherstellen."
            case .unusableBackupHint: "Diese Sicherung ist nicht lesbar und kann nicht wiederhergestellt werden."
            case .startFresh: "Neue Mediathek beginnen"
            case .startFreshConfirmationTitle: "Neue Mediathek beginnen?"
            case .startFreshConfirmationMessage: "Der aktuelle Katalog wird daneben aufbewahrt, nicht gelöscht. Ihre Fotodateien und Sicherungen bleiben, nur die Mediathekliste beginnt leer."
            case .startFreshFailed: "Neue Mediathek konnte nicht begonnen werden."
            }
        case .system:
            preconditionFailure("resolved language must not be system")
        }
    }
}
