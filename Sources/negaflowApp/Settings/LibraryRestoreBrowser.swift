import SwiftUI

struct LibraryRestoreBrowser: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var generations: [LibraryBackupGeneration] = []
    @State private var selectedID: String?
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var isWorking = false
    @State private var showRestoreConfirmation = false
    @State private var showScheduleError = false

    var body: some View {
        VStack(spacing: 12) {
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

            backupContent

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
                Button(model.text(AppLocalizedPhrase.done)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(model.text(AppLocalizedPhrase.libraryBackupRestoreSelected)) {
                    showRestoreConfirmation = true
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canScheduleSelected || isWorking)
            }
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 420)
        .task {
            await model.refreshScheduledLibraryRestore()
            await reload()
        }
        .alert(
            model.text(AppLocalizedPhrase.libraryBackupRestoreConfirmationTitle),
            isPresented: $showRestoreConfirmation
        ) {
            Button(model.text(AppLocalizedPhrase.cancel), role: .cancel) {}
            Button(model.text(AppLocalizedPhrase.libraryBackupScheduleRestore)) {
                Task { await scheduleSelectedRestore() }
            }
        } message: {
            Text(model.text(AppLocalizedPhrase.libraryBackupRestoreConfirmationMessage))
        }
        .alert(
            model.text(AppLocalizedPhrase.libraryBackupRestoreScheduleFailed),
            isPresented: $showScheduleError
        ) {
            Button(model.text(AppLocalizedPhrase.done), role: .cancel) {}
        }
    }

    @ViewBuilder
    private var backupContent: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if loadFailed {
            ContentUnavailableView(
                model.text(AppLocalizedPhrase.libraryBackupLoadFailed),
                systemImage: "exclamationmark.triangle"
            )
        } else if generations.isEmpty {
            ContentUnavailableView(
                model.text(AppLocalizedPhrase.libraryBackupEmpty),
                systemImage: "archivebox"
            )
        } else {
            List(generations, selection: $selectedID) { generation in
                LibraryBackupGenerationRow(generation: generation)
                    .tag(generation.id)
                    .disabled(!generation.state.isRestorable)
            }
        }
    }

    private var selectedGeneration: LibraryBackupGeneration? {
        guard let selectedID else { return nil }
        return generations.first { $0.id == selectedID }
    }

    private var canScheduleSelected: Bool {
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
    private func scheduleSelectedRestore() async {
        guard let selectedGeneration else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await model.scheduleLibraryRestore(generationID: selectedGeneration.id)
        } catch {
            showScheduleError = true
        }
    }

    @MainActor
    private func cancelPendingRestore() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await model.cancelScheduledLibraryRestore()
        } catch {
            showScheduleError = true
        }
    }

}
