import Foundation

struct SourceMetadataInspectorModel: Equatable {
    enum Origin: Equatable {
        case embedded
        case sidecar
        case mixed
        case unavailable
        case unknown
    }

    struct Field: Equatable {
        let value: String?
        let origin: Origin
    }

    let sidecarState: SourceXMPReadState?
    let hasReadProblem: Bool?
    let camera: Field
    let date: Field
    let title: Field
    let keywords: Field

    init(_ snapshot: SourceMetadataSnapshot?) {
        guard let snapshot else {
            sidecarState = nil
            hasReadProblem = nil
            camera = Field(value: nil, origin: .unknown)
            date = Field(value: nil, origin: .unknown)
            title = Field(value: nil, origin: .unknown)
            keywords = Field(value: nil, origin: .unknown)
            return
        }

        sidecarState = snapshot.sidecarXMPState
        hasReadProblem = snapshot.discardedInvalidValues
            || snapshot.discardedOversizedValues
            || [.invalid, .tooLarge, .ambiguous].contains(snapshot.sidecarXMPState)
        camera = Self.embeddedField([
            snapshot.exif?.cameraMake,
            snapshot.exif?.cameraModel,
            snapshot.exif?.lensModel,
        ])
        date = Self.dateField(snapshot)
        title = Self.titleField(snapshot)
        keywords = Self.keywordsField(snapshot)
    }

    private static func embeddedField(_ values: [String?]) -> Field {
        let value = joined(values.compactMap { $0 })
        return Field(value: value, origin: value == nil ? .unavailable : .embedded)
    }

    private static func dateField(_ snapshot: SourceMetadataSnapshot) -> Field {
        if snapshot.sidecarXMPState == .loaded,
           let value = first([snapshot.sidecarXMP?.dateCreatedRaw, snapshot.sidecarXMP?.createDateRaw]) {
            return Field(value: value, origin: .sidecar)
        }
        if let value = first([
            snapshot.exif?.dateTimeOriginalRaw.map {
                [$0, snapshot.exif?.offsetTimeOriginalRaw].compactMap { $0 }.joined(separator: " ")
            },
            snapshot.imageMetadataXMPView?.dateCreatedRaw,
            snapshot.imageMetadataXMPView?.createDateRaw,
        ]) {
            return Field(value: value, origin: .embedded)
        }
        return Field(value: nil, origin: .unavailable)
    }

    private static func titleField(_ snapshot: SourceMetadataSnapshot) -> Field {
        let sidecar = snapshot.sidecarXMPState == .loaded
            ? first([
                snapshot.sidecarXMP?.title?.defaultValue,
                snapshot.sidecarXMP?.headline,
                localizedValue(snapshot.sidecarXMP?.title),
            ])
            : nil
        let embedded = first([
            snapshot.iptc?.title,
            snapshot.iptc?.headline,
            snapshot.imageMetadataXMPView?.title?.defaultValue,
            snapshot.imageMetadataXMPView?.headline,
            localizedValue(snapshot.imageMetadataXMPView?.title),
        ])
        return mergedField(embedded: embedded, sidecar: sidecar)
    }

    private static func keywordsField(_ snapshot: SourceMetadataSnapshot) -> Field {
        let embedded = stableUnique(
            (snapshot.iptc?.keywords ?? []) + (snapshot.imageMetadataXMPView?.keywords ?? [])
        )
        let sidecar = snapshot.sidecarXMPState == .loaded
            ? stableUnique(snapshot.sidecarXMP?.keywords ?? [])
            : []
        return mergedField(
            embedded: joined(embedded),
            sidecar: joined(sidecar),
            combinesValues: true
        )
    }

    private static func mergedField(
        embedded: String?,
        sidecar: String?,
        combinesValues: Bool = false
    ) -> Field {
        switch (embedded, sidecar) {
        case let (embedded?, sidecar?):
            let value = combinesValues ? joined(stableUnique([embedded, sidecar])) : sidecar
            return Field(value: value, origin: .mixed)
        case let (embedded?, nil):
            return Field(value: embedded, origin: .embedded)
        case let (nil, sidecar?):
            return Field(value: sidecar, origin: .sidecar)
        case (nil, nil):
            return Field(value: nil, origin: .unavailable)
        }
    }

    private static func localizedValue(_ value: SourceLocalizedText?) -> String? {
        guard let value else { return nil }
        return value.valuesByLanguage.keys.sorted().compactMap {
            value.valuesByLanguage[$0]
        }.first
    }

    private static func first(_ values: [String?]) -> String? {
        values.compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }.first
    }

    private static func joined(_ values: [String]) -> String? {
        let values = stableUnique(values)
        return values.isEmpty ? nil : values.joined(separator: ", ")
    }

    private static func stableUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  seen.insert(trimmed.folding(options: [.caseInsensitive], locale: .current)).inserted
            else { return nil }
            return trimmed
        }
    }
}
