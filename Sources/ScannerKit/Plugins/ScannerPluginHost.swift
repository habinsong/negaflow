import Foundation
import CryptoKit
import Darwin

// MARK: - ScannerPluginHost
//
// 설치된 스캐너 플러그인을 파일시스템에서 발견한다. negaflow 는 스캐너 코드를 내장하지 않고,
// 이 호스트가 찾은 플러그인 실행파일과 JSON/CLI 프로토콜로만 통신한다.
public enum ScannerPluginHost {
    private static let maximumManifestBytes = 256 * 1_024
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
            guard hasSafeOwnershipAndPermissions(root, fileManager: fm),
                  let entries = try? fm.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            ) else { continue }

            for entry in entries {
                guard let entryValues = try? entry.resourceValues(
                    forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
                ), entryValues.isDirectory == true,
                   entryValues.isSymbolicLink != true,
                   hasSafeOwnershipAndPermissions(entry, fileManager: fm) else { continue }
                let manifestURL = entry.appendingPathComponent("manifest.json")
                guard let manifestValues = try? manifestURL.resourceValues(
                    forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
                ), manifestValues.isRegularFile == true,
                   manifestValues.isSymbolicLink != true,
                   hasSafeOwnershipAndPermissions(manifestURL, fileManager: fm),
                   let manifestSize = manifestValues.fileSize,
                   manifestSize > 0,
                   manifestSize <= maximumManifestBytes,
                      let data = try? Data(contentsOf: manifestURL),
                      data.count <= maximumManifestBytes,
                      let manifest = try? JSONDecoder().decode(ScannerPluginManifest.self, from: data)
                else { continue }
                guard manifest.isSupportedByHost else { continue }
                guard (manifest.kind ?? "scanner") == "scanner" else { continue }
                guard ScannerPluginManifest.isValidPluginID(manifest.id),
                      !manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !manifest.executable.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else { continue }
                guard !seenIDs.contains(manifest.id) else { continue }

                let exec = resolveExecutable(manifest.executable, relativeTo: entry)
                guard let exec,
                      let executableValues = try? exec.resourceValues(
                        forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
                      ), executableValues.isRegularFile == true,
                      executableValues.isSymbolicLink != true,
                      hasSafeOwnershipAndPermissions(exec, fileManager: fm),
                      fm.isExecutableFile(atPath: exec.path),
                      let executableSHA256 = sha256(of: exec),
                      let manifestSHA256 = sha256(data)
                else { continue }

                seenIDs.insert(manifest.id)
                found.append(InstalledScannerPlugin(
                    manifest: manifest,
                    manifestURL: manifestURL,
                    executableURL: exec,
                    trustIdentity: ScannerPluginTrustIdentity(
                        pluginID: manifest.id,
                        pluginVersion: manifest.pluginVersion,
                        manifestSHA256: manifestSHA256,
                        executableSHA256: executableSHA256
                    )
                ))
            }
        }
        return found
    }

    /// 발견 이후 manifest 또는 실행파일이 교체됐는지 현재 바이트에서 다시 계산한다.
    /// 실행 직전에 이 값이 승인 당시 identity와 같은지 확인해야 discovery→launch 사이 교체를
    /// 조용히 실행하지 않는다.
    public static func currentTrustIdentity(
        for plugin: InstalledScannerPlugin,
        fileManager: FileManager = .default
    ) -> ScannerPluginTrustIdentity? {
        let directory = plugin.manifestURL.deletingLastPathComponent()
        guard hasSafeOwnershipAndPermissions(
            directory.deletingLastPathComponent(),
            fileManager: fileManager
        ), let directoryValues = try? directory.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        ), directoryValues.isDirectory == true,
              directoryValues.isSymbolicLink != true,
              hasSafeOwnershipAndPermissions(directory, fileManager: fileManager),
              let manifestValues = try? plugin.manifestURL.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
              ), manifestValues.isRegularFile == true,
              manifestValues.isSymbolicLink != true,
              hasSafeOwnershipAndPermissions(plugin.manifestURL, fileManager: fileManager),
              let manifestSize = manifestValues.fileSize,
              manifestSize > 0,
              manifestSize <= maximumManifestBytes,
              let manifestData = try? Data(contentsOf: plugin.manifestURL),
              manifestData.count <= maximumManifestBytes,
              let manifest = try? JSONDecoder().decode(
                ScannerPluginManifest.self,
                from: manifestData
              ), manifest == plugin.manifest,
              let resolvedExecutable = resolveExecutable(
                manifest.executable,
                relativeTo: directory
              ), resolvedExecutable.standardizedFileURL == plugin.executableURL.standardizedFileURL,
              let executableValues = try? plugin.executableURL.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
              ), executableValues.isRegularFile == true,
              executableValues.isSymbolicLink != true,
              hasSafeOwnershipAndPermissions(plugin.executableURL, fileManager: fileManager),
              fileManager.isExecutableFile(atPath: plugin.executableURL.path),
              let manifestSHA256 = sha256(manifestData),
              let executableSHA256 = sha256(of: plugin.executableURL) else {
            return nil
        }
        return ScannerPluginTrustIdentity(
            pluginID: manifest.id,
            pluginVersion: manifest.pluginVersion,
            manifestSHA256: manifestSHA256,
            executableSHA256: executableSHA256
        )
    }

    private static func resolveExecutable(_ path: String, relativeTo dir: URL) -> URL? {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\0") else { return nil }
        let components = NSString(string: path).pathComponents
        guard !components.isEmpty,
              components.allSatisfy({ $0 != "." && $0 != ".." && $0 != "/" }) else {
            return nil
        }
        let resolvedDirectory = dir.resolvingSymlinksInPath().standardizedFileURL
        let candidate = dir.appendingPathComponent(path).standardizedFileURL
        let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard resolvedCandidate.deletingLastPathComponent().path == resolvedDirectory.path
                || resolvedCandidate.path.hasPrefix(resolvedDirectory.path + "/") else {
            return nil
        }
        return candidate
    }

    /// 사용자 Application Support 플러그인은 현재 사용자 소유이며 group/other 쓰기가 없어야 한다.
    /// 승인된 바이트가 다른 로컬 계정에 의해 교체될 수 있는 설치는 discovery 단계에서 제외한다.
    private static func hasSafeOwnershipAndPermissions(
        _ url: URL,
        fileManager: FileManager
    ) -> Bool {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let owner = (attributes[.ownerAccountID] as? NSNumber)?.uint32Value,
              let permissions = (attributes[.posixPermissions] as? NSNumber)?.uint16Value else {
            return false
        }
        return owner == getuid() && permissions & 0o022 == 0
    }

    private static func sha256(_ data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        do {
            while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
                hasher.update(data: data)
            }
        } catch {
            return nil
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
