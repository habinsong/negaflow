import Foundation
import Chromabase

// MARK: - FrameStorageNaming
//
// 디스크 저장 폴더/파일명 규칙(순수 함수). 모든 저장 폴더(썸네일/내보내기/빠른 내보내기/스캔)는
// "<날짜(yyyyMMdd)>/<출처>" 구조를 공유한다 — 출처는 이미지 가져오기=default, 폴더 가져오기=
// 폴더명이다. 스캔 원본은 "<날짜>/<필름 타입>/<필름명>" 구조를 쓴다.
enum FrameStorageNaming {
    /// 출처를 알 수 없을 때만 쓰는 출처 폴더명.
    static let defaultImportGroup = "default"

    /// 가져온 파일의 출처 폴더명 = 원본이 놓여 있던 폴더 이름.
    ///
    /// 예전에는 개별 파일 가져오기를 전부 `default` 로 묶었다. 그래서 한 폴더의 사진이라도
    /// 파일로 먼저 가져온 것만 `default/` 로, 나중에 폴더째 가져온 나머지는 폴더명으로 갈라져
    /// 내보내기 결과가 두 곳에 나뉘었다. 출처는 가져온 방식이 아니라 원본이 있던 자리로 정한다.
    static func importGroupName(forSourceURL url: URL) -> String {
        let parent = url.resolvingSymlinksInPath()
            .standardizedFileURL
            .deletingLastPathComponent()
            .lastPathComponent
        let sanitized = sanitizeComponent(parent)
        return sanitized.isEmpty ? defaultImportGroup : sanitized
    }

    /// 저장에 쓸 출처 폴더명. `default` 로만 남아 있는 예전 프레임(출처 미상 sentinel)은 원본이
    /// 놓여 있던 폴더로 해석한다 — 카탈로그를 고쳐 쓰지 않고도 같은 폴더의 사진이 한곳으로 모인다.
    static func resolvedGroupName(storedGroup: String?, sourceURL: URL) -> String {
        let sanitized = sanitizeComponent(storedGroup ?? "")
        if !sanitized.isEmpty, sanitized != defaultImportGroup { return sanitized }
        return importGroupName(forSourceURL: sourceURL)
    }

    /// 저장 폴더용 날짜 이름(예: 20260709). 사용자의 현재 캘린더/타임존 기준.
    static func dateFolderName(for date: Date = Date(), calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// 스캐너 표시명 → 폴더/파일명용 축약명.
    /// 괄호 주석을 제거하고, 제조사 접두어를 덜어낸 뒤 공백 없이 이어붙인다.
    /// 예: "Plustek OpticFilm 8200i (Demo)" → "OpticFilm8200i"
    static func scannerAbbreviation(_ displayName: String) -> String {
        var name = displayName
        while let open = name.firstIndex(of: "("), let close = name[open...].firstIndex(of: ")") {
            name.removeSubrange(open...close)
        }
        var tokens = name.split(whereSeparator: { $0 == " " || $0 == "_" }).map(String.init)
        let vendors: Set<String> = [
            "plustek", "epson", "canon", "nikon", "fujifilm", "fuji", "noritsu",
            "kodak", "reflecta", "pacific", "microtek", "hp", "brother",
        ]
        if tokens.count > 1, vendors.contains(tokens[0].lowercased()) {
            tokens.removeFirst()
        }
        let sanitized = sanitizeComponent(tokens.joined())
        let fallback = "scanner"
        guard !sanitized.isEmpty else { return fallback }
        return String(sanitized.prefix(24))
    }

    /// 필름명 도입 전 자동 생성하던 "<스캐너 축약명> <yyyyMMdd>" 롤 이름인지 판별한다.
    static func isLegacyScannerRollName(_ name: String, scannerAbbreviation: String) -> Bool {
        let prefix = "\(scannerAbbreviation) "
        guard name.hasPrefix(prefix) else { return false }
        let dateSuffix = name.dropFirst(prefix.count)
        return dateSuffix.count == 8 && dateSuffix.allSatisfy(\.isNumber)
    }

    /// 파일/폴더명에 쓸 수 없는 문자(경로 구분자·제어문자 등)를 제거한다.
    static func sanitizeComponent(_ raw: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
            .union(.controlCharacters)
            .union(.newlines)
        let cleaned = raw.unicodeScalars.filter { !invalid.contains($0) }
        return String(String.UnicodeScalarView(cleaned)).trimmingCharacters(in: .whitespaces)
    }

    /// 스캔 필름 종류 → 스캔 세부 폴더명(언어와 무관하게 경로가 안정되도록 ASCII 고정).
    static func filmTypeFolderName(_ filmType: FilmType) -> String {
        switch filmType {
        case .colorNegative: "color-negative"
        case .colorPositive: "color-slide"
        case .bwNegative: "bw-negative"
        case .bwPositive: "bw-slide"
        }
    }

    static func storedFilmType(forSourceURL sourceURL: URL) -> FilmType? {
        storedFilmType(
            forFilmFolderURL: sourceURL.deletingLastPathComponent()
        )
    }

    static func storedFilmType(forFilmFolderURL filmFolderURL: URL) -> FilmType? {
        let folderName = filmFolderURL
            .standardizedFileURL
            .deletingLastPathComponent()
            .lastPathComponent
        return FilmType.allCases.first {
            filmTypeFolderName($0) == folderName
        }
    }

    /// 같은 이름의 기존 필름 폴더에 서로 다른 롤을 섞지 않도록 사용 가능한 이름을 찾는다.
    static func availableFilmFolderName(
        _ requestedName: String,
        in parent: URL,
        fileManager: FileManager = .default
    ) -> String {
        let sanitized = sanitizeComponent(requestedName)
        let base = sanitized.isEmpty ? "Untitled Film" : sanitized
        let first = parent.appendingPathComponent(base, isDirectory: true)
        guard fileManager.fileExists(atPath: first.path) else { return base }
        var suffix = 2
        while fileManager.fileExists(
            atPath: parent.appendingPathComponent("\(base) \(suffix)", isDirectory: true).path
        ) {
            suffix += 1
        }
        let availableName = "\(base) \(suffix)"
        return availableName
    }

    /// 스캔 파일 기본명: "<스캐너 축약명>_frame_<번호>". 번호는 폴더의 기존 파일에서 이어 붙인다(1부터).
    static func scanFileBaseName(prefix: String, number: Int) -> String {
        "\(prefix)_frame_\(number)"
    }

    /// 폴더 안의 "<접두어>_frame_<n>" 파일들을 훑어 다음 번호를 정한다. 폴더가 없거나 비어 있으면 1.
    static func nextFrameNumber(in folder: URL, prefix: String, fileManager: FileManager = .default) -> Int {
        guard let names = try? fileManager.contentsOfDirectory(atPath: folder.path) else { return 1 }
        let marker = "\(prefix)_frame_"
        let numbers = names.compactMap { name -> Int? in
            guard name.hasPrefix(marker) else { return nil }
            let digits = name.dropFirst(marker.count).prefix(while: { $0.isNumber })
            return digits.isEmpty ? nil : Int(digits)
        }
        return (numbers.max() ?? 0) + 1
    }
}
