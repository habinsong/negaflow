import Foundation
import Chromabase
import ScannerKit

struct MetadataSearchSnapshot {
    let contentDate: Date?
    let contentCalendarDate: LibraryCalendarDate?
    let contentCalendarDateInterval: LibraryCalendarDateInterval?
    let hasContentDateMetadata: Bool
    let camera: [String]
    let lens: [String]
    let keywords: [String]
    let titleDescription: [String]
    let allSearchable: [String]
    let presentFields: Set<LibraryMetadataField>
    let unknownFields: Set<LibraryMetadataField>
    let unknownTextFields: Set<LibraryTextField>
    let hasReadProblem: Bool?

    init(_ snapshot: SourceMetadataSnapshot?, overlay: AppMetadataOverlay? = nil) {
        guard let snapshot else {
            contentDate = nil
            contentCalendarDate = nil
            contentCalendarDateInterval = nil
            hasContentDateMetadata = false
            camera = Self.shotCameraValues(overlay?.filmShot)
            lens = [overlay?.filmShot?.lensModel].compactMap { $0 }
            keywords = overlay?.keywords ?? []
            titleDescription = [overlay?.title, overlay?.caption].compactMap { $0 }
            allSearchable = Self.stableUnique(
                titleDescription + keywords + [overlay?.copyright].compactMap { $0 }
                    + camera + lens + Self.shotSearchValues(overlay?.filmShot)
            )
            var fields: Set<LibraryMetadataField> = []
            if overlay?.title != nil { fields.insert(.title) }
            if overlay?.caption != nil { fields.insert(.description) }
            if !(overlay?.keywords.isEmpty ?? true) { fields.insert(.keywords) }
            if !camera.isEmpty { fields.insert(.camera) }
            if !lens.isEmpty { fields.insert(.lens) }
            if overlay != nil { fields.insert(.descriptive) }
            presentFields = fields
            unknownFields = Set(LibraryMetadataField.allCases).subtracting(fields)
            var textUnknown: Set<LibraryTextField> = []
            if camera.isEmpty { textUnknown.insert(.camera) }
            if lens.isEmpty { textUnknown.insert(.lens) }
            if !fields.contains(.keywords) { textUnknown.insert(.keywords) }
            if !fields.contains(.title) || !fields.contains(.description) {
                textUnknown.insert(.titleDescription)
            }
            if !fields.contains(.descriptive) { textUnknown.insert(.anySearchable) }
            unknownTextFields = textUnknown
            hasReadProblem = nil
            return
        }

        let sidecar = snapshot.sidecarXMPState == .loaded ? snapshot.sidecarXMP : nil
        let resolvedContentDate = Self.resolveContentDate(snapshot, sidecar: sidecar)
        contentDate = resolvedContentDate.value?.instant
        hasContentDateMetadata = resolvedContentDate.value != nil
        contentCalendarDate = resolvedContentDate.value.flatMap { value in
            guard let month = value.wallClock.month,
                  let day = value.wallClock.day else { return nil }
            return LibraryCalendarDate(
                year: value.wallClock.year,
                month: month,
                day: day
            )
        }
        contentCalendarDateInterval = resolvedContentDate.value.flatMap {
            Self.calendarDateInterval(for: $0.wallClock)
        }
        // 촬영 기록(사용자가 적은 카메라·렌즈)은 원본 EXIF와 같은 자격으로 검색된다. 필름 카메라는
        // EXIF를 남기지 않으므로, 적어 둔 값이 곧 그 프레임의 카메라다.
        let cameraParts = [snapshot.exif?.cameraMake, snapshot.exif?.cameraModel]
            .compactMap { $0 }
        camera = Self.stableUnique(
            cameraParts + [cameraParts.joined(separator: " ")].filter { !$0.isEmpty }
                + Self.shotCameraValues(overlay?.filmShot)
        )
        lens = Self.stableUnique(
            [snapshot.exif?.lensModel, overlay?.filmShot?.lensModel].compactMap { $0 }
        )
        keywords = Self.stableUnique(
            (snapshot.iptc?.keywords ?? [])
                + (snapshot.imageMetadataXMPView?.keywords ?? [])
                + (sidecar?.keywords ?? [])
                + (overlay?.keywords ?? [])
        )

        let iptcTitles = [snapshot.iptc?.title, snapshot.iptc?.headline, snapshot.iptc?.caption]
            .compactMap { $0 }
        let imageTitles = Self.titleDescriptionValues(snapshot.imageMetadataXMPView)
        let sidecarTitles = Self.titleDescriptionValues(sidecar)
        titleDescription = Self.stableUnique(
            iptcTitles + imageTitles + sidecarTitles
                + [overlay?.title, overlay?.caption].compactMap { $0 }
        )

        let iptcText = Self.iptcValues(snapshot.iptc)
        let imageXMPText = Self.xmpValues(snapshot.imageMetadataXMPView)
        let sidecarText = Self.xmpValues(sidecar)
        let exifText = camera + lens
            + [snapshot.exif?.software].compactMap { $0 }
            + [snapshot.exif?.dateTimeOriginalRaw, snapshot.exif?.offsetTimeOriginalRaw]
                .compactMap { $0 }
        allSearchable = Self.stableUnique(
            exifText + iptcText + imageXMPText + sidecarText
                + [overlay?.title, overlay?.caption, overlay?.copyright].compactMap { $0 }
                + (overlay?.keywords ?? [])
                + Self.shotSearchValues(overlay?.filmShot)
        )

        var fields: Set<LibraryMetadataField> = [.snapshot]
        if !camera.isEmpty { fields.insert(.camera) }
        if !lens.isEmpty { fields.insert(.lens) }
        if hasContentDateMetadata { fields.insert(.contentDate) }
        if Self.hasTitle(snapshot.iptc, image: snapshot.imageMetadataXMPView, sidecar: sidecar) {
            fields.insert(.title)
        }
        if Self.hasDescription(snapshot.iptc, image: snapshot.imageMetadataXMPView, sidecar: sidecar) {
            fields.insert(.description)
        }
        if !keywords.isEmpty { fields.insert(.keywords) }
        if overlay?.title != nil { fields.insert(.title) }
        if overlay?.caption != nil { fields.insert(.description) }
        if !allSearchable.isEmpty { fields.insert(.descriptive) }
        presentFields = fields
        let readProblem = snapshot.discardedInvalidValues
            || snapshot.discardedOversizedValues
            || [.invalid, .tooLarge, .ambiguous].contains(snapshot.sidecarXMPState)
            || resolvedContentDate.hadReadProblem
        hasReadProblem = readProblem
        unknownFields = readProblem
            ? Set(LibraryMetadataField.allCases).subtracting(fields)
            : []
        var textUnknown = Set<LibraryTextField>()
        if unknownFields.contains(.camera) { textUnknown.insert(.camera) }
        if unknownFields.contains(.lens) { textUnknown.insert(.lens) }
        if unknownFields.contains(.keywords) { textUnknown.insert(.keywords) }
        if unknownFields.contains(.title) || unknownFields.contains(.description) {
            textUnknown.insert(.titleDescription)
        }
        if unknownFields.contains(.descriptive) { textUnknown.insert(.anySearchable) }
        unknownTextFields = textUnknown
    }

    /// 적어 둔 카메라 — 제조사, 모델, "제조사 모델" 모두로 찾을 수 있어야 한다.
    private static func shotCameraValues(_ shot: FilmShotMetadata?) -> [String] {
        guard let shot else { return [] }
        let parts = [shot.cameraMake, shot.cameraModel].compactMap { $0 }
        return stableUnique(parts + [parts.joined(separator: " ")].filter { !$0.isEmpty })
    }

    /// 필름 이름과 ISO도 검색어가 된다("Portra 400으로 찍은 컷").
    private static func shotSearchValues(_ shot: FilmShotMetadata?) -> [String] {
        guard let shot else { return [] }
        return stableUnique(
            [shot.filmStock, shot.isoSpeed.map(String.init)].compactMap { $0 }
        )
    }

    private static func resolveContentDate(
        _ snapshot: SourceMetadataSnapshot,
        sidecar: SourceXMPMetadata?
    ) -> (value: SourceContentDateValue?, hadReadProblem: Bool) {
        let candidates: [SourceContentDateParseResult] = [
            SourceMetadataReader.parseXMPContentDate(sidecar?.dateCreatedRaw),
            SourceMetadataReader.parseEXIFContentDate(
                dateTimeRaw: snapshot.exif?.dateTimeOriginalRaw,
                offsetRaw: snapshot.exif?.offsetTimeOriginalRaw,
                subsecondRaw: snapshot.exif?.subsecondTimeOriginalRaw
            ),
            SourceMetadataReader.parseXMPContentDate(
                snapshot.imageMetadataXMPView?.dateCreatedRaw
            ),
        ]
        var hadReadProblem = false
        var selectedValue: SourceContentDateValue?
        for candidate in candidates {
            switch candidate {
            case .absent:
                continue
            case .invalid:
                hadReadProblem = true
            case let .valid(value, hadInvalidSupplementalValue):
                hadReadProblem = hadReadProblem || hadInvalidSupplementalValue
                if selectedValue == nil { selectedValue = value }
            }
        }
        return (selectedValue, hadReadProblem: hadReadProblem)
    }

    private static func calendarDateInterval(
        for wallClock: SourceWallClockDateTime
    ) -> LibraryCalendarDateInterval? {
        guard let month = wallClock.month else {
            guard let first = LibraryCalendarDate(year: wallClock.year, month: 1, day: 1),
                  let last = LibraryCalendarDate(year: wallClock.year, month: 12, day: 31) else {
                return nil
            }
            return LibraryCalendarDateInterval(firstInclusive: first, lastInclusive: last)
        }
        guard let day = wallClock.day else {
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = Locale(identifier: "en_US_POSIX")
            calendar.timeZone = .gmt
            guard let firstDate = calendar.date(from: DateComponents(
                calendar: calendar,
                timeZone: .gmt,
                year: wallClock.year,
                month: month,
                day: 1
            )),
            let dayRange = calendar.range(of: .day, in: .month, for: firstDate),
            let first = LibraryCalendarDate(year: wallClock.year, month: month, day: 1),
            let last = LibraryCalendarDate(
                year: wallClock.year,
                month: month,
                day: dayRange.count
            ) else {
                return nil
            }
            return LibraryCalendarDateInterval(firstInclusive: first, lastInclusive: last)
        }
        guard let date = LibraryCalendarDate(
            year: wallClock.year,
            month: month,
            day: day
        ) else { return nil }
        return LibraryCalendarDateInterval(date)
    }

    private static func localizedValues(_ text: SourceLocalizedText?) -> [String] {
        guard let text else { return [] }
        return text.valuesByLanguage.keys.sorted().compactMap { text.valuesByLanguage[$0] }
    }

    private static func titleDescriptionValues(_ xmp: SourceXMPMetadata?) -> [String] {
        guard let xmp else { return [] }
        return localizedValues(xmp.title)
            + localizedValues(xmp.description)
            + [xmp.headline].compactMap { $0 }
    }

    private static func iptcValues(_ iptc: SourceIPTCMetadata?) -> [String] {
        guard let iptc else { return [] }
        return [
            iptc.title, iptc.headline, iptc.caption, iptc.credit,
            iptc.copyrightNotice, iptc.rightsUsageTerms, iptc.source,
            iptc.jobIdentifier, iptc.city, iptc.stateProvince, iptc.country,
            iptc.countryCode, iptc.sublocation,
        ].compactMap { $0 } + iptc.creators + iptc.keywords
    }

    private static func xmpValues(_ xmp: SourceXMPMetadata?) -> [String] {
        guard let xmp else { return [] }
        return [xmp.createDateRaw, xmp.dateCreatedRaw, xmp.headline, xmp.credit,
                xmp.jobIdentifier, xmp.city, xmp.stateProvince, xmp.country, xmp.sublocation,
                xmp.label]
            .compactMap { $0 }
            + localizedValues(xmp.title)
            + localizedValues(xmp.description)
            + localizedValues(xmp.rights)
            + localizedValues(xmp.usageTerms)
            + xmp.creators
            + xmp.keywords
    }

    private static func hasTitle(
        _ iptc: SourceIPTCMetadata?,
        image: SourceXMPMetadata?,
        sidecar: SourceXMPMetadata?
    ) -> Bool {
        [iptc?.title, iptc?.headline, image?.headline, sidecar?.headline]
            .contains { $0?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
            || !localizedValues(image?.title).isEmpty
            || !localizedValues(sidecar?.title).isEmpty
    }

    private static func hasDescription(
        _ iptc: SourceIPTCMetadata?,
        image: SourceXMPMetadata?,
        sidecar: SourceXMPMetadata?
    ) -> Bool {
        iptc?.caption?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || !localizedValues(image?.description).isEmpty
            || !localizedValues(sidecar?.description).isEmpty
    }

    private static func stableUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { value in
            let normalized = LibrarySearchText.normalize(value)
            return !normalized.isEmpty && seen.insert(normalized).inserted
        }
    }
}
