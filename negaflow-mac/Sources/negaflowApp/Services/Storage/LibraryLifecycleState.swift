enum LibraryLifecycleState: Equatable {
    case idle
    case restoring
    case ready
    case blocked
}

enum LibraryTerminationDecision: Equatable {
    case terminateNow
    case terminateLater
    case terminateCancel
}

struct LibraryCatalogPersistenceError: Error, Equatable {
    let generation: UInt64
}
