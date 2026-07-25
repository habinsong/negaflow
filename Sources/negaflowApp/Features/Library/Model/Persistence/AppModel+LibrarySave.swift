import AppKit
import Combine
import CoreImage
import Foundation
import Chromabase
import ScannerKit

extension AppModel {
    func scheduleLibrarySave() {
        scheduleLibrarySave(markDirty: true)
    }

    func scheduleLibrarySave(markDirty: Bool) {
        if let reason = libraryCatalogBlockReason {
            statusMessage = libraryCatalogBlockMessage(reason)
            return
        }
        guard libraryPersistenceEnabled else { return }
        if markDirty {
            markLibraryCatalogDirty()
        }
        if isAcknowledgedLibraryTransactionActive {
            librarySaveRequestedDuringTransaction = true
            return
        }
        guard librarySaveTask == nil else { return }
        librarySaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self, !Task.isCancelled else { return }
            self.librarySaveTask = nil
            self.saveLibrary(
                synchronous: false,
                generation: self.libraryCatalogDirtyGeneration
            )
        }
    }

    /// 카탈로그 저장. 레코드 스냅샷/인코딩은 메인(값 복사, 소량), 파일 쓰기는 백그라운드.
    /// synchronous = 앱 종료 경로(프로세스가 끝나기 전에 디스크에 닿아야 함).
    @discardableResult
    func saveLibrary(synchronous: Bool) -> Bool {
        saveLibrary(synchronous: synchronous, generation: nil)
    }

    @discardableResult
    private func saveLibrary(synchronous: Bool, generation: UInt64?) -> Bool {
        if let reason = libraryCatalogBlockReason {
            statusMessage = libraryCatalogBlockMessage(reason)
            return false
        }
        guard libraryPersistenceEnabled else { return false }
        if isAcknowledgedLibraryTransactionActive {
            librarySaveRequestedDuringTransaction = true
            return false
        }
        if hasUncommittedDefectGesture {
            scheduleLibrarySave(markDirty: false)
            return false
        }
        let trace = AppDiagnostics.start(.catalogSave, category: .catalog)
        let writeGeneration: UInt64
        if let generation {
            writeGeneration = generation
        } else if hasUnsavedLibraryChanges {
            writeGeneration = libraryCatalogDirtyGeneration
        } else {
            writeGeneration = markLibraryCatalogDirty()
        }
        guard let catalog = currentLibraryCatalogSnapshot() else {
            statusMessage = libraryCatalogBlockMessage(.corrupt)
            recordLibraryCatalogWriteResult(generation: writeGeneration, succeeded: false)
            trace.fail(code: "catalog_snapshot_invalid")
            return false
        }
        let url = libraryCatalogURL
        if synchronous {
            let succeeded = LibraryCatalogFile.writeCatalogSync(catalog, to: url)
            if succeeded {
                LibraryCatalogSQLiteWriteCache.shared.markSafetyValidated(catalog, for: url)
            }
            recordLibraryCatalogWriteResult(generation: writeGeneration, succeeded: succeeded)
            if succeeded {
                trace.finish()
            } else {
                trace.fail(code: "catalog_write_failed")
            }
            return succeeded
        } else {
            LibraryCatalogFile.writeCatalogAsync(catalog, to: url) { [weak self] succeeded in
                Task { @MainActor [weak self] in
                    if succeeded {
                        LibraryCatalogSQLiteWriteCache.shared.markSafetyValidated(catalog, for: url)
                    }
                    self?.recordLibraryCatalogWriteResult(
                        generation: writeGeneration,
                        succeeded: succeeded
                    )
                    if succeeded {
                        trace.finish()
                    } else {
                        trace.fail(code: "catalog_write_failed")
                    }
                }
            }
            // 비동기 enqueue는 저장 완료가 아니다. 실제 결과는 generation 상태에 반영된다.
            return false
        }
    }

    func retryLibrarySave() {
        guard libraryCatalogPersistenceError != nil,
              hasUnsavedLibraryChanges else { return }
        librarySaveTask?.cancel()
        librarySaveTask = nil
        _ = saveLibrary(
            synchronous: false,
            generation: libraryCatalogDirtyGeneration
        )
    }


}
