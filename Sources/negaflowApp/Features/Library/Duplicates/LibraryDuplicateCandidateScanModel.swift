import Foundation

@MainActor
final class LibraryDuplicateCandidateScanModel: ObservableObject {
    @Published var isPresented = false
    @Published private(set) var isScanning = false
    @Published private(set) var report: LibraryDuplicateCandidateReport?
    @Published private(set) var failed = false
    private var task: Task<Void, Never>?

    func start(inputs: [LibraryDuplicateCandidateInput]) {
        task?.cancel()
        report = nil
        failed = false
        isScanning = true
        isPresented = true
        task = Task {
            do {
                let result = try await LibraryDuplicateCandidateScanner.scan(inputs)
                guard !Task.isCancelled else { return }
                report = result
            } catch is CancellationError {
                return
            } catch {
                failed = true
            }
            isScanning = false
        }
    }

    func dismiss() {
        task?.cancel()
        task = nil
        isScanning = false
        isPresented = false
    }
}
