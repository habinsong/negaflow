import SwiftUI

struct LibraryDuplicateCandidateSheet: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var scanModel: LibraryDuplicateCandidateScanModel
    let onSelect: ([UUID]) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.duplicateText(.title))
                    .font(.title3.weight(.semibold))
                Spacer()
                Button(model.duplicateText(.close)) { scanModel.dismiss() }
            }
            .padding(16)
            Divider()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 620, minHeight: 420)
    }

    @ViewBuilder
    private var content: some View {
        if scanModel.isScanning {
            ProgressView(model.duplicateText(.scanning))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let report = scanModel.report {
            if report.groups.isEmpty {
                ContentUnavailableView(
                    model.duplicateText(.none),
                    systemImage: "doc.on.doc"
                )
            } else {
                List {
                    summary(report)
                    ForEach(report.groups) { group in
                        Section {
                            ForEach(group.members) { member in
                                Text(verbatim: member.sourceURL.path)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                            }
                            Button(model.duplicateText(.selectGroup)) {
                                onSelect(group.members.map(\.frameID))
                            }
                        } header: {
                            Text(model.duplicateText(.exactBytes, group.fileSizeBytes))
                        }
                    }
                }
            }
        } else if scanModel.failed {
            ContentUnavailableView(
                model.duplicateText(.failed),
                systemImage: "exclamationmark.triangle"
            )
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func summary(_ report: LibraryDuplicateCandidateReport) -> some View {
        Section {
            Text(model.duplicateText(
                .summary,
                report.groups.count,
                report.inspectedFileCount
            ))
            if report.skippedUnavailableCount > 0 {
                Text(model.duplicateText(.unavailable, report.skippedUnavailableCount))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
