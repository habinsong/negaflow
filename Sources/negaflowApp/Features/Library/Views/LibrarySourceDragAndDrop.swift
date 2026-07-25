import AppKit
import os
import SwiftUI
import UniformTypeIdentifiers

private let dragLog = Logger(subsystem: "com.songhabin.negaflow", category: "dragdrop")

extension UTType {
    static let negaflowLibrarySource = UTType(exportedAs: "com.negaflow.library-source")
}

struct LibrarySourceDragItem: Codable, Sendable {
    let frameIDs: [UUID]

    init(frameIDs: [UUID]) {
        self.frameIDs = frameIDs
    }

    func itemProvider() -> NSItemProvider {
        guard let data = try? JSONEncoder().encode(self) else {
            return NSItemProvider()
        }
        return NSItemProvider(
            item: data as NSData,
            typeIdentifier: UTType.negaflowLibrarySource.identifier
        )
    }

    static func decode(_ data: Data) -> LibrarySourceDragItem? {
        try? JSONDecoder().decode(LibrarySourceDragItem.self, from: data)
    }
}

struct LibrarySourceDraggableModifier: ViewModifier {
    let item: LibrarySourceDragItem

    func body(content: Content) -> some View {
        content.onDrag {
            item.itemProvider()
        } preview: {
            HStack(spacing: 7) {
                Image(systemName: "photo.on.rectangle.angled")
                Text(verbatim: "\(item.frameIDs.count)")
                    .monospacedDigit()
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .adaptiveCapsuleSurface(.regular)
        }
    }
}

struct LibrarySourceDropDestinationModifier: ViewModifier {
    @EnvironmentObject private var model: AppModel
    @State private var isTargeted = false
    @State private var didAcceptDrop = false
    let destinationFolder: URL
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .onDrop(
                of: [.negaflowLibrarySource],
                delegate: LibrarySourceDropDelegate(
                    isTargeted: $isTargeted,
                    didAcceptDrop: $didAcceptDrop,
                    handle: handle
                )
            )
            .overlay {
                if isTargeted || didAcceptDrop {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.accentColor, lineWidth: 2)
                        .background(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(Color.accentColor.opacity(isTargeted ? 0.14 : 0.08))
                        )
                        .allowsHitTesting(false)
                }
            }
            .scaleEffect(isTargeted ? 1.04 : (didAcceptDrop ? 1.022 : 1))
            .animation(.spring(response: 0.20, dampingFraction: 0.58), value: isTargeted)
            .animation(.spring(response: 0.24, dampingFraction: 0.62), value: didAcceptDrop)
    }

    private func handle(_ item: LibrarySourceDragItem) -> Bool {
        dragLog.notice("handle: frameIDs=\(item.frameIDs.count) mutation=\(model.allowsLibraryMutation)")
        guard model.allowsLibraryMutation else { return false }
        let frameIDs = Set(item.frameIDs)
        let frames = model.frames.filter { frameIDs.contains($0.id) }
        dragLog.notice("handle: matched frames=\(frames.count)")
        guard !frames.isEmpty else { return false }
        guard frames.contains(where: {
            $0.rawScanURL.deletingLastPathComponent().standardizedFileURL
                != destinationFolder.standardizedFileURL
        }) else {
            dragLog.notice("handle: all frames already in destination")
            return false
        }
        dragLog.notice("handle: moving to \(destinationFolder.path)")
        model.moveSourceFiles(for: frames, to: destinationFolder)
        return true
    }
}

private struct LibrarySourceDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    @Binding var didAcceptDrop: Bool
    let handle: (LibrarySourceDragItem) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.negaflowLibrarySource])
    }

    func dropEntered(info: DropInfo) {
        dragLog.notice("dropEntered: valid=\(validateDrop(info: info))")
        guard validateDrop(info: info), !isTargeted else { return }
        withAnimation(.spring(response: 0.20, dampingFraction: 0.58)) {
            isTargeted = true
        }
        NSHapticFeedbackManager.defaultPerformer.perform(
            .alignment,
            performanceTime: .now
        )
    }

    func dropExited(info: DropInfo) {
        withAnimation(.spring(response: 0.20, dampingFraction: 0.72)) {
            isTargeted = false
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard validateDrop(info: info) else {
            dragLog.notice("dropUpdated: invalid")
            return nil
        }
        // .move는 드래그 소스의 허용 마스크에 없으면 AppKit이 드롭 자체를 거부할 수 있다.
        // 실제 파일 이동은 handle에서 수행하므로 제안은 항상 수용되는 .copy를 쓴다.
        return DropProposal(operation: .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        let providers = info.itemProviders(for: [.negaflowLibrarySource])
        dragLog.notice("performDrop: providers=\(providers.count)")
        guard !providers.isEmpty else { return false }

        for provider in providers {
            dragLog.notice("performDrop: registered=\(provider.registeredTypeIdentifiers)")
            provider.loadDataRepresentation(
                forTypeIdentifier: UTType.negaflowLibrarySource.identifier
            ) { data, error in
                dragLog.notice("performDrop: data=\(data?.count ?? -1) error=\(String(describing: error))")
                guard let data, let item = LibrarySourceDragItem.decode(data) else { return }
                Task { @MainActor in
                    guard handle(item) else { return }
                    withAnimation(.spring(response: 0.20, dampingFraction: 0.58)) {
                        didAcceptDrop = true
                    }
                    NSHapticFeedbackManager.defaultPerformer.perform(
                        .alignment,
                        performanceTime: .now
                    )
                    try? await Task.sleep(for: .milliseconds(240))
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                        didAcceptDrop = false
                    }
                }
            }
        }
        return true
    }
}

/// 창 전체 파일 가져오기 드롭. 내부 라이브러리 드래그(.negaflowLibrarySource)는
/// 폴더 행 드롭 대상이 파일 이동으로 처리해야 하므로 여기서는 거부한다.
struct ExternalFileImportDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let handle: ([NSItemProvider]) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        !info.hasItemsConforming(to: [.negaflowLibrarySource])
            && info.hasItemsConforming(to: [.fileURL])
    }

    func dropEntered(info: DropInfo) {
        isTargeted = validateDrop(info: info)
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        validateDrop(info: info) ? DropProposal(operation: .copy) : nil
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        guard validateDrop(info: info) else { return false }
        return handle(info.itemProviders(for: [.fileURL]))
    }
}

extension View {
    func librarySourceDraggable(item: LibrarySourceDragItem) -> some View {
        modifier(LibrarySourceDraggableModifier(item: item))
    }

    func librarySourceDropDestination(
        destinationFolder: URL,
        cornerRadius: CGFloat = 7
    ) -> some View {
        modifier(LibrarySourceDropDestinationModifier(
            destinationFolder: destinationFolder,
            cornerRadius: cornerRadius
        ))
    }
}
