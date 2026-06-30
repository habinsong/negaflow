import Foundation
import Chromabase
import CoreGraphics
import CoreImage
import ImageIO

extension SANEBackend {
    static func findScanimage() -> String {
        let candidates = [
            "/opt/homebrew/bin/scanimage",
            "/usr/local/bin/scanimage",
            "/usr/bin/scanimage",
        ]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) { return c }
        return "scanimage"
    }

    /// SANE 설정 디렉토리(dll.conf, genesys.conf 등이 있는 곳)를 찾는다.
    /// Homebrew 로 설치한 경우 기본 컴파일 경로에 없으므로 SANE_CONFIG_DIR 가 필요하다.
    /// scanimage 가 이 디렉토리를 못 찾으면 "open of device failed: Invalid argument".
    static func findSaneConfigDir() -> String? {
        // 1) 환경변수가 이미 있으면 그대로 사용.
        if let v = ProcessInfo.processInfo.environment["SANE_CONFIG_DIR"],
           FileManager.default.fileExists(atPath: v) { return v }
        // 2) Homebrew 표준 경로 후보.
        let overrideConfigDir = ProcessInfo.processInfo.environment["NEGAFLOW_SCANIMAGE_PATH"]
            .map {
                URL(fileURLWithPath: $0)
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .appendingPathComponent("etc/sane.d")
                    .path
            }
        let candidates = [
            overrideConfigDir,
            "/opt/homebrew/etc/sane.d",
            "/usr/local/etc/sane.d",
            "/etc/sane.d",
        ].compactMap { $0 }
        for c in candidates {
            if FileManager.default.fileExists(atPath: c) { return c }
        }
        return nil
    }

    /// GUI .app 환경에서는 기본 PATH 가 /usr/bin:/bin 뿐이라 scanimage 가
    /// 의존하는 동적 라이브러리(libsane)나 SANE_CONFIG_DIR 를 못 찾는다.
    /// 따라서 Process 에 명시적으로 환경을 주입한다.
    static func makeSaneEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        // Homebrew 경로를 PATH 앞에 추가(libsane*.dylib 해석 + 일반 도구 접근).
        let toolPrefix = ProcessInfo.processInfo.environment["NEGAFLOW_SCANIMAGE_PATH"]
            .map { URL(fileURLWithPath: $0).deletingLastPathComponent().path }
        let pathPrefixes = [toolPrefix, "/opt/homebrew/bin", "/opt/homebrew/sbin"]
            .compactMap { $0 }
            .joined(separator: ":")
        let existing = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = "\(pathPrefixes):\(existing)"
        // SANE 설정 디렉토리.
        if let cfg = findSaneConfigDir() {
            env["SANE_CONFIG_DIR"] = cfg
        }
        // 백엔드 라이브러리 경로(SANE가 .so/.dylib 를 찾는 위치).
        let overrideLibDir = ProcessInfo.processInfo.environment["NEGAFLOW_SCANIMAGE_PATH"]
            .map { URL(fileURLWithPath: $0).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("lib/sane").path }
        let libdirs = [overrideLibDir, "/opt/homebrew/lib/sane", "/usr/local/lib/sane"]
            .compactMap { $0 }
            .filter { FileManager.default.fileExists(atPath: $0) }
        if !libdirs.isEmpty, env["SANE_BACKENDS_PATH"] == nil {
            env["SANE_BACKENDS_PATH"] = libdirs.joined(separator: ":")
        }
        return env
    }

    public static func makeTempURL(prefix: String, suffix: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("\(prefix)_\(UUID().uuidString)\(suffix)")
    }

    public static func imageSize(at url: URL) -> (Int, Int) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any],
              let w = props["PixelWidth"] as? Int,
              let h = props["PixelHeight"] as? Int
        else { return (0, 0) }
        return (w, h)
    }
}
