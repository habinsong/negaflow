import SwiftUI

enum AppTypography {
    static let minimumTextPointSize: CGFloat = 10
    static let minimumScaleFactor: CGFloat = 0.92

    static let compactIcon = Font.system(size: 9)
    static let microIcon = Font.system(size: 7, weight: .bold)

    static func minimumText(weight: Font.Weight = .regular) -> Font {
        .system(size: minimumTextPointSize, weight: weight)
    }
}
