import Foundation

// MARK: - ScannerPluginHost
//
// 설치된 스캐너 플러그인을 파일시스템에서 발견한다. negaflow 는 스캐너 코드를 내장하지 않고,
// 이 호스트가 찾은 플러그인 실행파일과 JSON/CLI 프로토콜로만 통신한다.
public enum ScannerPluginHost {
    /// 플러그인 루트 디렉토리. `NEGAFLOW_PLUGINS_DIR` 환경변수가 있으면 그 경로만 사용해 기본 경로를
    /// 완전히 대체한다(테스트/개발/샌드박스 격리 — 시스템 설치본과 섞이지 않는다). 없으면 기본 위치를 쓴다.
    public static func pluginDirectories() -> [URL] {
        if let override = ProcessInfo.processInfo.environment["NEGAFLOW_PLUGINS_DIR"], !override.isEmpty {
            return [URL(fileURLWithPath: override, isDirectory: true)]
        }
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return []
        }
        return [appSupport
            .appendingPathComponent("negaflow", isDirectory: true)
            .appendingPathComponent("Plugins", isDirectory: true)]
    }

    /// 사용자용 설치 디렉토리(플러그인 install 스크립트가 여기에 복사).
    public static var defaultInstallDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("negaflow", isDirectory: true)
            .appendingPathComponent("Plugins", isDirectory: true)
    }

    /// 설치된 스캐너 플러그인을 발견한다(manifest 파싱 + 실행파일 해석 + 실행권한 확인).
    /// 같은 id 는 우선순위가 높은 디렉토리의 것만 채택한다.
    public static func discover() -> [InstalledScannerPlugin] {
        let fm = FileManager.default
        var found: [InstalledScannerPlugin] = []
        var seenIDs = Set<String>()

        for root in pluginDirectories() {
            guard let entries = try? fm.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            ) else { continue }

            for entry in entries {
                let manifestURL = entry.appendingPathComponent("manifest.json")
                guard fm.fileExists(atPath: manifestURL.path),
                      let data = try? Data(contentsOf: manifestURL),
                      let manifest = try? JSONDecoder().decode(ScannerPluginManifest.self, from: data)
                else { continue }
                guard (manifest.kind ?? "scanner") == "scanner" else { continue }
                guard !seenIDs.contains(manifest.id) else { continue }

                let exec = resolveExecutable(manifest.executable, relativeTo: entry)
                guard let exec, fm.isExecutableFile(atPath: exec.path) else { continue }

                seenIDs.insert(manifest.id)
                found.append(InstalledScannerPlugin(
                    manifest: manifest, manifestURL: manifestURL, executableURL: exec
                ))
            }
        }
        return found
    }

    private static func resolveExecutable(_ path: String, relativeTo dir: URL) -> URL? {
        guard !path.isEmpty else { return nil }
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        return dir.appendingPathComponent(path)
    }
}
