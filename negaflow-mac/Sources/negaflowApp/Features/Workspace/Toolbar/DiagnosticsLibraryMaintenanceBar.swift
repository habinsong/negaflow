import SwiftUI

/// 진단 패널 맨 아래 한 줄: 왼쪽 카탈로그 수동 복구, 오른쪽 카탈로그 재설치. 모양은 현상 탭의
/// 자동 톤/자동 화이트 밸런스와 같고, 각 알약 오른쪽 단추는 카탈로그 파일을 Finder에서 연다.
struct DiagnosticsLibraryMaintenanceBar: View {
    @EnvironmentObject private var model: AppModel
    /// 내보내기 진행 여부는 모델 밖 저장소가 발행한다. 관찰하지 않으면 내보내는 동안에도 단추가
    /// 켜져 보이고 눌러도 아무 일이 없다.
    @ObservedObject var exportBatchStore: ExportBatchStore

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
            ],
            spacing: 8
        ) {
            QuickActionPill(
                title: model.text(AppLocalizedPhrase.libraryCatalogRepairAction),
                systemImage: "wrench.and.screwdriver",
                help: model.text(AppLocalizedPhrase.libraryCatalogRepairHelp),
                trailingSystemImage: "folder",
                trailingHelp: revealHelp,
                isActionEnabled: model.canRunLibraryCatalogMaintenance,
                action: { Task { await model.repairLibraryCatalogAndRelaunch() } },
                trailingAction: { model.revealLibraryCatalogInFinder() }
            )
            .accessibilityIdentifier("negaflow.diagnostics.catalogRepair")

            QuickActionPill(
                title: model.text(AppLocalizedPhrase.libraryCatalogReinstallAction),
                systemImage: "arrow.triangle.2.circlepath",
                help: model.text(AppLocalizedPhrase.libraryCatalogReinstallHelp),
                trailingSystemImage: "folder",
                trailingHelp: revealHelp,
                isActionEnabled: model.canRunLibraryCatalogMaintenance,
                action: { Task { await model.reinstallLibraryCatalogAndRelaunch() } },
                trailingAction: { model.revealLibraryCatalogInFinder() }
            )
            .accessibilityIdentifier("negaflow.diagnostics.catalogReinstall")
        }
        .controlSize(.large)
    }

    private var revealHelp: String {
        model.text(AppLocalizedPhrase.showInFinder) + " — " + model.abbreviatedLibraryCatalogPath
    }
}
