import Chromabase
import SwiftUI

enum QuickStartHelpScene {
    static let windowID = "quick-start-help"
}

struct QuickStartHelpView: View {
    @EnvironmentObject private var model: AppModel

    private var document: QuickStartHelpDocument {
        .current(for: model.appLanguage)
    }

    private var content: QuickStartHelpContent {
        document.content
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                ForEach(content.steps) { step in
                    helpStep(step)
                }

                Divider()

                HStack {
                    Text(content.shortcutNote)
                    Spacer()
                    Text(content.versionLabel + " " + document.version)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(32)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .frame(minWidth: 560, minHeight: 480)
        .accessibilityIdentifier("help.quickStart")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(content.title)
                .font(.largeTitle.weight(.semibold))
            Text(content.introduction)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private func helpStep(_ step: QuickStartHelpContent.Step) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: step.systemImage)
                .font(.title2)
                .frame(width: 28)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(step.title)
                    .font(.headline)
                Text(step.detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
