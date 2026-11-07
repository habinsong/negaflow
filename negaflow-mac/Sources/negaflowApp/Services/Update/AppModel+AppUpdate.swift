import AppKit
import SwiftUI
import Chromabase
import Foundation

/// 업데이트 확인 결과만 따로 발행한다. 툴바의 더보기 메뉴만 이것을 본다.
@MainActor
final class AppUpdateStore: ObservableObject {
    /// nil = 아직 모르거나 확인에 실패했다. 실패를 "최신"으로 보이지 않는다.
    @Published fileprivate(set) var result: AppUpdateCheckResult?
    @Published fileprivate(set) var isDownloading = false
    fileprivate var didStartCheck = false
}

extension AppModel {
    /// 실행할 때 한 번만 묻는다. 결과를 기다리지 않고 시작을 이어 간다.
    func checkForAppUpdateOnLaunch() {
        guard !appUpdateStore.didStartCheck else { return }
        appUpdateStore.didStartCheck = true
        let currentVersion = NegaflowProductVersion.applicationVersion()
        Task { [weak self] in
            let result = await Self.fetchAppUpdate(currentVersion: currentVersion)
            self?.appUpdateStore.result = result
        }
    }

    nonisolated static func fetchAppUpdate(currentVersion: String) async -> AppUpdateCheckResult? {
        var request = URLRequest(url: AppUpdateCheck.latestReleaseAPI, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // GitHub API 는 User-Agent 없는 요청을 거절한다.
        request.setValue("negaflow/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return AppUpdateCheck.result(
                latestReleaseJSON: data,
                currentVersion: currentVersion,
                isAppleSilicon: isAppleSilicon
            )
        } catch {
            return nil
        }
    }

    nonisolated static var isAppleSilicon: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        // Rosetta 아래에서 돌아도 기계가 Apple Silicon 이면 1 이다.
        if sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 { return value == 1 }
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    /// 더보기 메뉴의 업데이트 항목. 새 버전이면 릴리스 페이지를 열고 설치 파일을 받는다.
    /// 최신이면 프로젝트 페이지를 연다. 설치는 사용자가 한다.
    func performAppUpdateMenuAction() {
        switch appUpdateStore.result {
        case .available(let release):
            NSWorkspace.shared.open(release.pageURL)
            downloadAppUpdate(release)
        case .upToDate:
            if let url = AboutNegaflowView.repositoryURL {
                NSWorkspace.shared.open(url)
            }
        case nil:
            break
        }
    }

    private func downloadAppUpdate(_ release: AppUpdateRelease) {
        guard let installer = release.installer, !appUpdateStore.isDownloading else { return }
        appUpdateStore.isDownloading = true
        statusMessage = text(AppLocalizedPhrase.updateDownloadingFormat, installer.name)
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        Task { [weak self] in
            let saved = await Self.downloadVerifiedInstaller(
                installer,
                checksums: release.checksums,
                into: downloads
            )
            guard let self else { return }
            self.appUpdateStore.isDownloading = false
            if let saved {
                self.statusMessage = self.text(AppLocalizedPhrase.updateDownloadedFormat, saved.lastPathComponent)
                NSWorkspace.shared.activateFileViewerSelecting([saved])
            } else {
                // 스캔 상태(scanPhase)는 건드리지 않는다 — 업데이트 실패는 스캔 오류가 아니다.
                let message = self.text(AppLocalizedPhrase.updateDownloadFailed)
                self.statusMessage = message
                self.errorLog.record(message)
            }
        }
    }

    /// 받고, 릴리스의 SHA-256 과 맞는지 보고, 다운로드 폴더에 덮어쓰지 않는 이름으로 옮긴다.
    /// 체크섬 파일이 없거나 맞지 않으면 받은 파일을 버린다.
    nonisolated static func downloadVerifiedInstaller(
        _ installer: AppUpdateRelease.Asset,
        checksums: AppUpdateRelease.Asset?,
        into folder: URL?
    ) async -> URL? {
        guard let folder, let checksums else { return nil }
        do {
            let (sumsData, sumsResponse) = try await URLSession.shared.data(from: checksums.downloadURL)
            guard (sumsResponse as? HTTPURLResponse)?.statusCode == 200,
                  let sums = String(data: sumsData, encoding: .utf8),
                  let expected = AppUpdateCheck.expectedSHA256(in: sums, fileName: installer.name)
            else { return nil }
            let (temporary, response) = try await URLSession.shared.download(from: installer.downloadURL)
            defer { try? FileManager.default.removeItem(at: temporary) }
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  try AppUpdateCheck.sha256Hex(of: temporary) == expected else { return nil }
            // 다운로드 폴더가 지워졌거나 옮겨져 없으면 옮기기가 실패한다 — 만들어 두고 옮긴다.
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = AppUpdateCheck.availableDestination(in: folder, fileName: installer.name)
            try FileManager.default.moveItem(at: temporary, to: destination)
            return destination
        } catch {
            return nil
        }
    }
}

/// 더보기 메뉴 맨 아래의 업데이트 항목. 확인 전이거나 실패했으면 아무것도 보이지 않는다.
struct AppUpdateMenuItem: View {
    @ObservedObject var store: AppUpdateStore
    let model: AppModel

    var body: some View {
        switch store.result {
        case .available(let release):
            Divider()
            Button {
                model.performAppUpdateMenuAction()
            } label: {
                Label(
                    model.text(AppLocalizedPhrase.updateAvailableFormat, release.version),
                    systemImage: "arrow.down.circle"
                )
            }
            .disabled(store.isDownloading)
        case .upToDate:
            Divider()
            Button {
                model.performAppUpdateMenuAction()
            } label: {
                Label(model.text(AppLocalizedPhrase.updateUpToDate), systemImage: "checkmark.circle")
            }
        case nil:
            EmptyView()
        }
    }
}
