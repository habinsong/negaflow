import CryptoKit
import Foundation

/// GitHub 최신 릴리스 하나. 버전은 태그에서 읽고(`v1.2.7` → `1.2.7`), 앱에 박아 두지 않는다.
struct AppUpdateRelease: Equatable, Sendable {
    struct Asset: Equatable, Sendable {
        let name: String
        let downloadURL: URL
    }

    let version: String
    let pageURL: URL
    /// 이 Mac 에 맞는 설치 파일. 릴리스에 없으면 nil 이고, 그때는 페이지만 연다.
    let installer: Asset?
    /// 릴리스에 함께 올라간 `SHA256SUMS.txt`. 받은 파일을 이것으로 확인한다.
    let checksums: Asset?
}

enum AppUpdateCheckResult: Equatable, Sendable {
    case upToDate
    case available(AppUpdateRelease)
}

/// 업데이트 확인의 순수한 부분: 응답 해석, 버전 비교, 설치 파일 고르기, 체크섬 대조.
/// 네트워크와 파일 이동은 `AppModel+AppUpdate` 가 맡는다.
enum AppUpdateCheck {
    static let latestReleaseAPI = URL(string: "https://api.github.com/repos/habinsong/negaflow/releases/latest")!

    private struct ReleasePayload: Decodable {
        struct AssetPayload: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let tag_name: String
        let html_url: URL
        let draft: Bool?
        let prerelease: Bool?
        let assets: [AssetPayload]
    }

    /// `releases/latest` 응답을 읽어 지금 버전과 비교한다. 해석할 수 없으면 nil.
    static func result(
        latestReleaseJSON data: Data,
        currentVersion: String,
        isAppleSilicon: Bool
    ) -> AppUpdateCheckResult? {
        guard let payload = try? JSONDecoder().decode(ReleasePayload.self, from: data),
              payload.draft != true,
              payload.prerelease != true,
              let remote = versionComponents(payload.tag_name),
              let local = versionComponents(currentVersion) else { return nil }
        guard compare(remote, local) > 0 else { return .upToDate }
        let assets = payload.assets.map { Asset(name: $0.name, url: $0.browser_download_url) }
        return .available(AppUpdateRelease(
            version: remote.map(String.init).joined(separator: "."),
            pageURL: payload.html_url,
            installer: installer(in: assets, isAppleSilicon: isAppleSilicon),
            checksums: assets.first { $0.name == "SHA256SUMS.txt" }
                .map { AppUpdateRelease.Asset(name: $0.name, downloadURL: $0.url) }
        ))
    }

    struct Asset: Equatable {
        let name: String
        let url: URL
    }

    /// Apple Silicon 이면 전용 PKG, 아니면 Universal PKG. 둘 다 없으면 nil.
    static func installer(in assets: [Asset], isAppleSilicon: Bool) -> AppUpdateRelease.Asset? {
        let suffixes = isAppleSilicon
            ? ["-mac-arm64.pkg", "-mac-universal.pkg"]
            : ["-mac-universal.pkg"]
        for suffix in suffixes {
            if let asset = assets.first(where: { $0.name.hasSuffix(suffix) }) {
                return AppUpdateRelease.Asset(name: asset.name, downloadURL: asset.url)
            }
        }
        return nil
    }

    /// `v1.2.7`, `1.2.7`, `1.2.7-beta` → [1, 2, 7]. 숫자가 아닌 마디가 있으면 nil.
    static func versionComponents(_ text: String) -> [Int]? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.first == "v" || value.first == "V" { value.removeFirst() }
        if let dash = value.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            value = String(value[..<dash])
        }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 4 else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isASCII), let number = Int(part), number >= 0 else {
                return nil
            }
            numbers.append(number)
        }
        return numbers
    }

    /// 빠진 마디는 0 으로 본다(1.3 == 1.3.0).
    static func compare(_ lhs: [Int], _ rhs: [Int]) -> Int {
        for index in 0..<max(lhs.count, rhs.count) {
            let a = index < lhs.count ? lhs[index] : 0
            let b = index < rhs.count ? rhs[index] : 0
            if a != b { return a < b ? -1 : 1 }
        }
        return 0
    }

    /// `SHA256SUMS.txt`(`shasum -a 256` 형식: `<hex>  <이름>`)에서 파일 하나의 해시.
    static func expectedSHA256(in sums: String, fileName: String) -> String? {
        for line in sums.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 2 else { continue }
            var name = String(fields[fields.count - 1])
            if name.hasPrefix("*") { name.removeFirst() }
            let hash = fields[0].lowercased()
            guard name == fileName, hash.count == 64, hash.allSatisfy(\.isHexDigit) else { continue }
            return hash
        }
        return nil
    }

    static func sha256Hex(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// 다운로드 폴더에 같은 이름이 있으면 덮지 않고 `이름 2.pkg` 처럼 비어 있는 이름을 고른다.
    static func availableDestination(in folder: URL, fileName: String,
                                     fileManager: FileManager = .default) -> URL {
        let first = folder.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: first.path) else { return first }
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var index = 2
        while true {
            let name = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            let candidate = folder.appendingPathComponent(name)
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
    }
}
