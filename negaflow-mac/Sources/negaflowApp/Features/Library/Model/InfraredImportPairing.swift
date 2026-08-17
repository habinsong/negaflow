import Foundation

// MARK: - InfraredImportPairing
//
// 가져오기 목록에서 "본 스캔 + IR(적외선) 채널" 짝을 찾아낸다.
//
// 스캔 경로는 IR 채널을 본 스캔 옆에 `<본스캔 파일명>.ir.tiff` 로 남기고, 다른 스캔
// 소프트웨어는 `<이름>_ir.tif` / `<이름>-infrared.tif` 처럼 쓴다. 가져오기가 이 규칙을
// 모르면 IR 이 사진 한 장으로 목록에 서고, 본 스캔에는 IR 이 붙지 않아 GrainMend IR 이
// 아예 돌지 않는다.
//
// 짝짓기는 **같은 폴더**에서, **짝이 되는 본 스캔이 실제로 있을 때만** 성립한다. 짝을 찾지
// 못한 IR 이름의 파일은 지금처럼 평범한 사진으로 들어온다 — 잘못 붙이는 것보다 사진 한 장으로
// 들어오는 편이 낫다.
enum InfraredImportPairing {
    /// IR 채널로 인정하는 확장자. 스캐너 IR 은 무손실 TIFF 로 나온다 — 이 제한이 `_ir.jpg`
    /// 같은 평범한 사진을 IR 로 오인하지 않게 막는다.
    static let infraredExtensions: Set<String> = ["tif", "tiff"]

    /// 파일명 끝에서 IR 을 표시하는 토큰. 앞에 구분자가 반드시 와야 한다(`noir.tiff` 오인 방지).
    private static let markers = ["infrared", "ir"]
    private static let separators: Set<Character> = [".", "_", "-"]

    struct Resolution: Sendable {
        /// 프레임이 될 파일(입력 순서 보존).
        var baseURLs: [URL] = []
        /// 본 스캔 identity(`AppModel.importIdentity`) → IR URL.
        var infraredByBaseIdentity: [String: URL] = [:]
        /// 짝이 성립해 목록에서 빠진 IR 파일.
        var pairedInfraredURLs: [URL] = []
    }

    /// - Parameters:
    ///   - urls: 이번 요청의 파일들(지원 확장자 필터를 이미 통과한 목록).
    ///   - existingBaseURLs: 이미 라이브러리에 있는 원본들. 본 스캔만 먼저 가져왔거나 같은
    ///     폴더를 다시 가져올 때도 IR 이 사진으로 서지 않게 한다.
    static func resolve(_ urls: [URL], existingBaseURLs: [URL] = []) -> Resolution {
        var index = CandidateIndex()
        for url in urls { index.add(url) }
        for url in existingBaseURLs { index.add(url) }

        var result = Resolution()
        var claimedBaseIdentities = Set<String>()
        var pairedInfraredIdentities = Set<String>()

        for url in urls {
            guard let core = infraredCoreName(url),
                  let base = index.match(core: core, excluding: url) else { continue }
            let baseIdentity = AppModel.importIdentity(base)
            // 한 본 스캔에는 IR 하나만 붙인다. 뒤따르는 후보는 평범한 사진으로 둔다.
            guard claimedBaseIdentities.insert(baseIdentity).inserted else { continue }
            pairedInfraredIdentities.insert(AppModel.importIdentity(url))
            result.infraredByBaseIdentity[baseIdentity] = url.standardizedFileURL
            result.pairedInfraredURLs.append(url)
        }
        result.baseURLs = urls.filter {
            !pairedInfraredIdentities.contains(AppModel.importIdentity($0))
        }
        return result
    }

    /// IR 표시를 떼어낸 본 스캔 이름(소문자). IR 이름이 아니면 nil.
    ///
    /// `foo.tiff.ir.tiff` → `foo.tiff`(스캔 경로), `foo_ir.tif` → `foo`(외부 스캔 소프트웨어).
    static func infraredCoreName(_ url: URL) -> String? {
        let standardized = url.standardizedFileURL
        guard infraredExtensions.contains(standardized.pathExtension.lowercased()) else { return nil }
        let stem = standardized.deletingPathExtension().lastPathComponent.lowercased()
        for marker in markers {
            guard stem.count > marker.count + 1, stem.hasSuffix(marker) else { continue }
            let separatorIndex = stem.index(stem.endIndex, offsetBy: -(marker.count + 1))
            guard separators.contains(stem[separatorIndex]) else { continue }
            let core = String(stem[stem.startIndex..<separatorIndex])
            return core.isEmpty ? nil : core
        }
        return nil
    }

    /// 폴더별 파일명/스템 색인. IR 은 본 스캔과 확장자가 다를 수 있어(`foo.tif` + `foo_ir.tiff`)
    /// 두 키가 모두 필요하다.
    private struct CandidateIndex {
        private var buckets: [String: [String: [URL]]] = [:]

        mutating func add(_ url: URL) {
            let standardized = url.standardizedFileURL
            let directory = AppModel.importIdentity(standardized.deletingLastPathComponent())
            let name = standardized.lastPathComponent.lowercased()
            let stem = standardized.deletingPathExtension().lastPathComponent.lowercased()
            append(standardized, directory: directory, key: name)
            if stem != name { append(standardized, directory: directory, key: stem) }
        }

        private mutating func append(_ url: URL, directory: String, key: String) {
            var bucket = buckets[directory] ?? [:]
            var urls = bucket[key] ?? []
            guard !urls.contains(where: { $0.path == url.path }) else { return }
            urls.append(url)
            bucket[key] = urls
            buckets[directory] = bucket
        }

        func match(core: String, excluding infraredURL: URL) -> URL? {
            let standardized = infraredURL.standardizedFileURL
            let directory = AppModel.importIdentity(standardized.deletingLastPathComponent())
            guard let bucket = buckets[directory] else { return nil }
            var matches = (bucket[core] ?? []).filter { $0.path != standardized.path }
            guard !matches.isEmpty else { return nil }
            if matches.count > 1 {
                // 스템만 같은 파일이 여러 개면 확장자가 같은 쪽을 고른다. 그래도 갈리면 짝을
                // 만들지 않는다.
                matches = matches.filter {
                    $0.pathExtension.lowercased() == standardized.pathExtension.lowercased()
                }
            }
            return matches.count == 1 ? matches[0] : nil
        }
    }
}
