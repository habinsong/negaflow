import Foundation

enum LocalAdjustmentLocalizedText {
    case title, add, edit, delete, copy, paste, dodge, burn, amount, feather, size
    case brush, radial, linear, polygon, finishPolygon, drawPrompt, empty, visibility

    func resolved(language: AppLanguage) -> String {
        switch language.resolved {
        case .system, .english:
            return english[index]
        case .korean:
            return korean[index]
        case .japanese:
            return japanese[index]
        case .simplifiedChinese:
            return chinese[index]
        case .french:
            return french[index]
        case .german:
            return german[index]
        }
    }

    private var index: Int {
        switch self {
        case .title: 0; case .add: 1; case .edit: 2; case .delete: 3; case .copy: 4; case .paste: 5
        case .dodge: 6; case .burn: 7; case .amount: 8; case .feather: 9; case .size: 10
        case .brush: 11; case .radial: 12; case .linear: 13; case .polygon: 14
        case .finishPolygon: 15; case .drawPrompt: 16; case .empty: 17; case .visibility: 18
        }
    }

    private var english: [String] { ["Local", "Add Local Adjustment", "Edit Local Adjustment", "Delete", "Copy", "Paste", "Dodge", "Burn", "Amount", "Feather", "Size", "Brush", "Radial", "Linear", "Polygon", "Finish Polygon", "Draw on the photo", "No local adjustments", "Visibility"] }
    private var korean: [String] { ["부분 보정", "부분 보정 추가", "부분 보정 편집", "삭제", "복사", "붙여넣기", "닷지", "번", "양", "페더", "크기", "브러시", "방사형", "선형", "다각형", "다각형 완료", "사진 위에 그리세요", "부분 보정 없음", "표시"] }
    private var japanese: [String] { ["部分補正", "部分補正を追加", "部分補正を編集", "削除", "コピー", "ペースト", "覆い焼き", "焼き込み", "量", "ぼかし", "サイズ", "ブラシ", "円形", "線形", "多角形", "多角形を完了", "写真上に描画", "部分補正なし", "表示"] }
    private var chinese: [String] { ["局部调整", "添加局部调整", "编辑局部调整", "删除", "复制", "粘贴", "减淡", "加深", "数量", "羽化", "大小", "画笔", "径向", "线性", "多边形", "完成多边形", "在照片上绘制", "无局部调整", "可见性"] }
    private var french: [String] { ["Local", "Ajouter un réglage local", "Modifier le réglage local", "Supprimer", "Copier", "Coller", "Éclaircir", "Assombrir", "Intensité", "Contour progressif", "Taille", "Pinceau", "Radial", "Linéaire", "Polygone", "Terminer le polygone", "Dessinez sur la photo", "Aucun réglage local", "Visibilité"] }
    private var german: [String] { ["Lokal", "Lokale Anpassung hinzufügen", "Lokale Anpassung bearbeiten", "Löschen", "Kopieren", "Einfügen", "Abwedeln", "Nachbelichten", "Stärke", "Weiche Kante", "Größe", "Pinsel", "Radial", "Linear", "Polygon", "Polygon abschließen", "Auf dem Foto zeichnen", "Keine lokalen Anpassungen", "Sichtbarkeit"] }
}
