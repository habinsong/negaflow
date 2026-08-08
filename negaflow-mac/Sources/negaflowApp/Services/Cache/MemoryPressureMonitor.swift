import Dispatch

final class MemoryPressureMonitor: @unchecked Sendable {
    private let source: any DispatchSourceMemoryPressure

    init(handler: @escaping @Sendable (FrameCachePressureLevel) -> Void) {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: .all,
            queue: DispatchQueue(label: "negaflow.memory-pressure", qos: .utility)
        )
        self.source = source
        source.setEventHandler { [weak source] in
            guard let source else { return }
            handler(FrameCachePressureLevel(event: source.data))
        }
        source.activate()
    }

    deinit {
        source.cancel()
    }
}
