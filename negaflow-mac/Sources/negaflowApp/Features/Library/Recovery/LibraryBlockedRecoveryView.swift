import SwiftUI

struct LibraryBlockedRecoveryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var generations: [LibraryBackupGeneration] = []
    @State private var selectedID: String?
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var isWorking = false
    @State private var showRestoreConfirmation = false
    @State private var showRestoreError = false
    @State private var showStartFreshConfirmation = false
    @State private var showStartFreshError = false
    @State private var ambiguousDeleteTransactionID: UUID?
    @State private var showAmbiguousDeleteConfirmation = false
    @State private var showAmbiguousRecoveryError = false
    @State private var copiedDiagnostics = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LibraryRecoveryHeader(
                reason: blockReasonText,
                catalogPath: model.abbreviatedLibraryCatalogPath,
                isWorking: isWorking,
                copiedDiagnostics: copiedDiagnostics,
                retry: { Task { await retryOpen() } },
                reveal: { model.revealLibraryCatalogInFinder() },
                copyDiagnostics: {
                    Task {
                        await model.copyLibraryRecoveryDiagnostics(generations: generations)
                        copiedDiagnostics = true
                    }
                }
            )

            Divider()

            if !model.preservableExportCommitTransactionIDs.isEmpty {
                ambiguousExportRecoverySection
                Divider()
            }

            HStack {
                Text(model.text(AppLocalizedPhrase.diskLibraryBackupLabel))
                    .font(.headline)
                Spacer()
                Button {
                    Task { await reload() }
                } label: {
                    Label(
                        model.text(AppLocalizedPhrase.libraryBackupRefresh),
                        systemImage: "arrow.clockwise"
                    )
                }
                .labelStyle(.iconOnly)
                .help(model.text(AppLocalizedPhrase.libraryBackupRefresh))
                .disabled(isLoading || isWorking)
            }

            LibraryRecoveryBackupList(
                isLoading: isLoading,
                loadFailed: loadFailed,
                generations: generations,
                selectedID: $selectedID
            )

            if model.libraryPendingRestoreMarker != nil {
                HStack {
                    Label(
                        model.text(AppLocalizedPhrase.libraryBackupRestorePending),
                        systemImage: "clock.arrow.circlepath"
                    )
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button(model.text(AppLocalizedPhrase.libraryBackupCancelPending)) {
                        Task { await cancelPendingRestore() }
                    }
                    .disabled(isWorking)
                }
            }

            HStack {
                Button(localized(.startFresh)) {
                    showStartFreshConfirmation = true
                }
                .accessibilityIdentifier("negaflow.recovery.startfresh")
                .disabled(isWorking)

                Spacer()

                if !canRestoreSelected {
                    Text(localized(.selectBackupHint))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(model.text(AppLocalizedPhrase.libraryBackupRestoreSelected)) {
                    showRestoreConfirmation = true
                }
                .accessibilityIdentifier("negaflow.recovery.restore")
                .keyboardShortcut(.defaultAction)
                .disabled(!canRestoreSelected || isWorking)
                .help(canRestoreSelected ? "" : localized(.selectBackupHint))
            }
        }
        .padding(24)
        .accessibilityIdentifier("negaflow.recovery")
        .accessibilityValue(model.accessibilityText(.blocked))
        .frame(maxWidth: 760, minHeight: 480, maxHeight: 620)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await reload() }
        .alert(
            model.text(AppLocalizedPhrase.libraryBackupRestoreConfirmationTitle),
            isPresented: $showRestoreConfirmation
        ) {
            Button(model.text(AppLocalizedPhrase.cancel), role: .cancel) {}
            Button(model.text(AppLocalizedPhrase.libraryBackupRestoreSelected)) {
                Task { await restoreSelected() }
            }
            .accessibilityIdentifier("negaflow.recovery.confirm")
        } message: {
            Text(model.text(AppLocalizedPhrase.libraryBackupRestoreConfirmationMessage))
        }
        .alert(
            model.text(AppLocalizedPhrase.libraryBackupRestoreScheduleFailed),
            isPresented: $showRestoreError
        ) {
            Button(model.text(AppLocalizedPhrase.done), role: .cancel) {}
        }
        .alert(
            model.text(.libraryAmbiguousExportDeleteConfirmationTitle),
            isPresented: $showAmbiguousDeleteConfirmation
        ) {
            Button(model.text(AppLocalizedPhrase.cancel), role: .cancel) {
                ambiguousDeleteTransactionID = nil
            }
            Button(model.text(.libraryAmbiguousExportDeleteFiles), role: .destructive) {
                Task { await deleteAmbiguousExportArtifacts() }
            }
            .accessibilityIdentifier("negaflow.recovery.export.delete.confirm")
        } message: {
            Text(model.text(.libraryAmbiguousExportDeleteConfirmationMessage))
        }
        .alert(
            model.text(.libraryAmbiguousExportRecoveryFailed),
            isPresented: $showAmbiguousRecoveryError
        ) {
            Button(model.text(AppLocalizedPhrase.done), role: .cancel) {}
        }
        .alert(
            localized(.startFreshConfirmationTitle),
            isPresented: $showStartFreshConfirmation
        ) {
            Button(model.text(AppLocalizedPhrase.cancel), role: .cancel) {}
            Button(localized(.startFresh)) {
                Task { await startFresh() }
            }
            .accessibilityIdentifier("negaflow.recovery.startfresh.confirm")
        } message: {
            Text(localized(.startFreshConfirmationMessage))
        }
        .alert(localized(.startFreshFailed), isPresented: $showStartFreshError) {
            Button(model.text(AppLocalizedPhrase.done), role: .cancel) {}
        }
    }

    private func localized(_ key: LibraryRecoveryLocalizedText) -> String {
        AppLocalization.libraryRecoveryText(key, language: model.appLanguage)
    }

    private var ambiguousExportRecoverySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.text(.libraryAmbiguousExportRecoveryTitle))
                        .font(.headline)
                    Text(model.text(.libraryAmbiguousExportRecoveryMessage))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                    .foregroundStyle(.orange)
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.preservableExportCommitTransactionIDs, id: \.self) {
                        transactionID in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.text(.libraryAmbiguousExportTransaction))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(verbatim: transactionID.uuidString)
                                    .font(.caption.monospaced())
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                            }

                            Spacer(minLength: 12)

                            Button(model.text(.libraryAmbiguousExportKeepFiles)) {
                                Task { await preserveAmbiguousExportArtifacts(transactionID) }
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier(
                                "negaflow.recovery.export.keep.\(transactionID.uuidString)"
                            )

                            if model.ambiguousExportCommitTransactionIDs.contains(transactionID) {
                                Button(
                                    model.text(.libraryAmbiguousExportDeleteFiles),
                                    role: .destructive
                                ) {
                                    ambiguousDeleteTransactionID = transactionID
                                    showAmbiguousDeleteConfirmation = true
                                }
                                .accessibilityIdentifier(
                                    "negaflow.recovery.export.delete.\(transactionID.uuidString)"
                                )
                            }
                        }
                        .padding(10)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .frame(maxHeight: 180)
            .disabled(isWorking)
        }
        .accessibilityIdentifier("negaflow.recovery.export")
    }

    private var blockReasonText: String {
        guard let reason = model.libraryCatalogBlockReason else {
            return model.text(AppLocalizedPhrase.libraryCatalogBlockedStatus)
        }
        return model.libraryCatalogBlockMessage(reason)
    }

    private var selectedGeneration: LibraryBackupGeneration? {
        guard let selectedID else { return nil }
        return generations.first { $0.id == selectedID }
    }

    private var canRestoreSelected: Bool {
        selectedGeneration?.state.isRestorable == true
    }

    @MainActor
    private func reload() async {
        isLoading = true
        loadFailed = false
        do {
            generations = try await model.libraryBackupGenerations()
            if let selectedID, !generations.contains(where: { $0.id == selectedID }) {
                self.selectedID = nil
            }
        } catch {
            generations = []
            loadFailed = true
        }
        isLoading = false
    }

    @MainActor
    private func retryOpen() async {
        isWorking = true
        copiedDiagnostics = false
        _ = await model.retryBlockedLibraryOpen()
        isWorking = false
        if model.libraryLifecycleState == .blocked {
            await reload()
        }
    }

    @MainActor
    private func restoreSelected() async {
        guard let selectedGeneration else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let restored = try await model.restoreBlockedLibraryBackup(
                generationID: selectedGeneration.id
            )
            if !restored {
                showRestoreError = true
                await reload()
            }
        } catch {
            showRestoreError = true
        }
    }

    @MainActor
    private func startFresh() async {
        isWorking = true
        defer { isWorking = false }
        guard await model.startFreshLibraryFromRecovery() else {
            showStartFreshError = true
            await reload()
            return
        }
    }

    @MainActor
    private func cancelPendingRestore() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await model.cancelScheduledLibraryRestore()
        } catch {
            showRestoreError = true
        }
    }

    @MainActor
    private func preserveAmbiguousExportArtifacts(_ transactionID: UUID) async {
        isWorking = true
        defer { isWorking = false }
        let resolved = await model.resolveAmbiguousExportCommitPreservingArtifacts(
            transactionID: transactionID
        )
        if resolved {
            if model.libraryLifecycleState == .blocked {
                await reload()
            }
        } else {
            showAmbiguousRecoveryError = true
        }
    }

    @MainActor
    private func deleteAmbiguousExportArtifacts() async {
        guard let transactionID = ambiguousDeleteTransactionID else { return }
        ambiguousDeleteTransactionID = nil
        isWorking = true
        defer { isWorking = false }
        let resolved = await model.resolveAmbiguousExportCommitDeletingOwnedArtifacts(
            transactionID: transactionID
        )
        if resolved {
            if model.libraryLifecycleState == .blocked {
                await reload()
            }
        } else {
            showAmbiguousRecoveryError = true
        }
    }
}
