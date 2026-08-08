extension AppModel {
    var frames: [ScanFrame] {
        get { frameStore.frames }
        set { frameStore.frames = newValue }
    }

    var allowsLibraryMutation: Bool {
        (libraryLifecycleState == .idle || libraryLifecycleState == .ready)
            && !isScanFinalizationInProgress
            && !isSourceMoveInProgress
    }

    var hasUnsavedLibraryChanges: Bool {
        libraryCatalogPersistedGeneration < libraryCatalogDirtyGeneration
    }

    @discardableResult
    func markLibraryCatalogDirty() -> UInt64 {
        libraryCatalogDirtyGeneration &+= 1
        return libraryCatalogDirtyGeneration
    }

    func recordLibraryCatalogWriteResult(generation: UInt64, succeeded: Bool) {
        guard generation > 0, generation <= libraryCatalogDirtyGeneration else { return }
        if succeeded {
            guard generation > libraryCatalogPersistedGeneration else { return }
            libraryCatalogPersistedGeneration = generation
            if let error = libraryCatalogPersistenceError,
               error.generation <= generation {
                libraryCatalogPersistenceError = nil
            }
            return
        }

        guard generation > libraryCatalogPersistedGeneration else { return }
        if let error = libraryCatalogPersistenceError,
           error.generation > generation {
            return
        }
        libraryCatalogPersistenceError = LibraryCatalogPersistenceError(generation: generation)
    }

    func transitionLibraryLifecycle(to state: LibraryLifecycleState) {
        libraryLifecycleState = state
    }

    func advanceLibraryQueryGeneration() {
        libraryQueryGeneration &+= 1
    }

    func replaceLibraryOrganizerState(
        manualCollections: [LibraryManualCollection],
        smartCollections: [LibrarySmartCollection],
        savedSearches: [LibrarySavedSearch]
    ) {
        self.manualCollections = manualCollections
        self.smartCollections = smartCollections
        self.savedSearches = savedSearches
    }

    func replaceManualCollections(with collections: [LibraryManualCollection]) {
        manualCollections = collections
    }

    func replaceSmartCollections(with collections: [LibrarySmartCollection]) {
        smartCollections = collections
    }

    func replaceSavedSearches(with searches: [LibrarySavedSearch]) {
        savedSearches = searches
    }

    func advanceSourceAvailabilityRevision() {
        sourceAvailabilityRevision &+= 1
    }
}
