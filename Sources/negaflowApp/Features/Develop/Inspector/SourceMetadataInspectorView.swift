import SwiftUI

struct SourceMetadataInspectorView: View {
    @EnvironmentObject private var appModel: AppModel
    @ObservedObject var frame: ScanFrame

    private var metadata: SourceMetadataInspectorModel {
        SourceMetadataInspectorModel(frame.sourceMetadata)
    }

    var body: some View {
        InspectorCard {
            VStack(alignment: .leading, spacing: 10) {
                InspectorCardHeader(title: localized(.info), systemImage: "info.circle")
                row(.source, value: sourceValue, origin: nil)
                row(.sidecar, value: sidecarValue, origin: nil)
                row(.camera, field: metadata.camera)
                row(.date, field: metadata.date)
                row(.title, field: metadata.title)
                row(.keywords, field: metadata.keywords)
                if metadata.hasReadProblem == true {
                    Label(localized(.readProblem), systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var sourceValue: String {
        frame.sourceKind.originLabel(language: appModel.appLanguage)
            + " · " + frame.rawScanURL.lastPathComponent
    }

    private var sidecarValue: String {
        guard let state = metadata.sidecarState else { return localized(.unknown) }
        switch state {
        case .loaded: return localized(.loaded)
        case .notFound: return localized(.notFound)
        case .invalid: return localized(.invalid)
        case .tooLarge: return localized(.tooLarge)
        case .ambiguous: return localized(.ambiguous)
        }
    }

    private func row(_ label: SourceMetadataInspectorLocalizedText, field: SourceMetadataInspectorModel.Field) -> some View {
        row(label, value: field.value ?? localized(.notAvailable), origin: field.origin)
    }

    private func row(
        _ label: SourceMetadataInspectorLocalizedText,
        value: String,
        origin: SourceMetadataInspectorModel.Origin?
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(localized(label))
                .frame(width: 64, alignment: .leading)
            Text(singleLineValue(value, origin: origin))
                .lineLimit(1)
                .minimumScaleFactor(AppTypography.minimumScaleFactor)
                .allowsTightening(true)
                .truncationMode(.middle)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(.caption)
    }

    private func singleLineValue(
        _ value: String,
        origin: SourceMetadataInspectorModel.Origin?
    ) -> String {
        guard let origin else { return value }
        return value + " · " + originLabel(origin)
    }

    private func originLabel(_ origin: SourceMetadataInspectorModel.Origin) -> String {
        switch origin {
        case .embedded: localized(.embedded)
        case .sidecar: localized(.sidecarOrigin)
        case .mixed: localized(.mixed)
        case .unavailable: localized(.notAvailable)
        case .unknown: localized(.unknown)
        }
    }

    private func localized(_ text: SourceMetadataInspectorLocalizedText) -> String {
        text.resolved(language: appModel.appLanguage)
    }
}
