import Foundation

// MARK: - SaneConfigTuner (scanimage -L 속도 최적화)
//
// 근본 원인(실측):
//   Homebrew SANE 의 dll.conf 에 77개 백엔드 + net/escl 네트워크 프로브가 켜져 있다.
//   scanimage -L 은 이 전부를 매번 libusb/네트워크로 돌며 probe 한다 → 수초 지연.
//   Plustek OpticFilm 8200i 에는 genesys 백엔드 하나만 필요하다.
//
// 해결:
//   1. 원본 dll.conf 를 dll.conf.negaflow-backup 으로 백업
//   2. dll.conf 를 genesys(+pint 진단용)만 남기는 버전으로 교체
//   3. 결과: -L 가 수초 → 1초 이내
//
// 주의: dll.conf 는 Homebrew 심볼릭 링크(Cellar → etc/sane.d)일 수 있다.
// 링크를 진짜 파일로 교체해야 우리가 쓴 내용이 반영된다. 원본은 링크가 가리키던
// Cellar 파일을 백업 디렉토리에 복사해 둔다. 복구(Restore)도 지원한다.
public enum SaneConfigTuner {
    /// SANE 설정 디렉토리. makeSaneEnvironment 와 동일한 탐지 로직.
    public static var configDir: String {
        if let v = ProcessInfo.processInfo.environment["SANE_CONFIG_DIR"],
           FileManager.default.fileExists(atPath: v) { return v }
        for c in ["/opt/homebrew/etc/sane.d", "/usr/local/etc/sane.d", "/etc/sane.d"]
        where FileManager.default.fileExists(atPath: c) { return c }
        return "/opt/homebrew/etc/sane.d"
    }

    public static var dllConfPath: String { configDir + "/dll.conf" }
    public static var backupPath: String { configDir + "/dll.conf.negaflow-backup" }

    /// 8200i에 필요한 백엔드. genesys 필수, pint는 macOS 진단용.
    public static let requiredBackends: Set<String> = ["genesys", "pint"]

    public enum TuneResult: Equatable {
        case alreadyTuned
        case tuned(originalBackedUpTo: String)
        case notNeeded
        case failed(String)
    }

    /// dll.conf 를 genesys(+pint)만 남기도록 최적화. 이미 최적화됐으면 no-op.
    /// 원본은 backupPath 에 보존. idempotent.
    @discardableResult
    public static func tune() -> TuneResult {
        let fm = FileManager.default
        let dll = dllConfPath
        guard fm.fileExists(atPath: dll) else { return .notNeeded }

        // 현재 내용 읽기 (심볼릭 링크면 resolve 됨).
        guard let current = try? String(contentsOfFile: dll, encoding: .utf8) else {
            return .failed("dll.conf 읽기 실패: \(dll)")
        }

        // 이미 튜닝됐는지 확인: 주석 아닌 백엔드가 requiredBackends 부분집합이면.
        if isAlreadyTuned(current) {
            // 백업은 보존되어 있어야 함. 없으면 원본이 손실됐을 수 있으니 그대로 둠.
            return .alreadyTuned
        }

        // 원본 백업 (심볼릭 링크가 가리키는 실제 내용을 평문 파일로).
        // 백업이 이미 있으면 덮어쓰지 않는다(사용자가 수동 편집했을 수 있음).
        if !fm.fileExists(atPath: backupPath) {
            // 링크가 가리키는 진짜 파일을 복사.
            let resolved = (try? fm.destinationOfSymbolicLink(atPath: dll)) ?? dll
            let src = fm.fileExists(atPath: resolved) ? resolved : dll
            do {
                try fm.copyItem(atPath: src, toPath: backupPath)
            } catch {
                return .failed("백업 실패: \(error.localizedDescription)")
            }
        }

        // 새 dll.conf 내용 생성: 원본을 보존하되 비활성화 백엔드는 주석 처리.
        let tuned = rewriteKeepingOnly(required: requiredBackends, original: current)

        // 심볼릭 링크 제거 후 진짜 파일로 교체.
        if let _ = try? fm.destinationOfSymbolicLink(atPath: dll) {
            try? fm.removeItem(atPath: dll)
        }
        do {
            try tuned.write(toFile: dll, atomically: true, encoding: .utf8)
        } catch {
            return .failed("dll.conf 쓰기 실패: \(error.localizedDescription)")
        }
        return .tuned(originalBackedUpTo: backupPath)
    }

    /// 백업에서 dll.conf 를 원래대로 복구.
    @discardableResult
    public static func restore() -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: backupPath) else { return false }
        do {
            // 현재(튜닝된) dll.conf 제거 후 백업으로 교체.
            try? fm.removeItem(atPath: dllConfPath)
            try fm.copyItem(atPath: backupPath, toPath: dllConfPath)
            return true
        } catch {
            return false
        }
    }

    public static var isTuned: Bool {
        guard let current = try? String(contentsOfFile: dllConfPath, encoding: .utf8) else {
            return false
        }
        return isAlreadyTuned(current)
    }

    /// 현재 활성(주석 아닌) 백엔드 목록.
    public static var activeBackends: [String] {
        guard let current = try? String(contentsOfFile: dllConfPath, encoding: .utf8) else {
            return []
        }
        return current.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .map { $0.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? $0 }
    }

    // MARK: - helpers
    static func isAlreadyTuned(_ content: String) -> Bool {
        let active = content.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .map { $0.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? $0 }
        let activeSet = Set(active)
        // 활성 백엔드가 requiredBackends 의 부분집합이면 튜닝됨.
        return activeSet.isSubset(of: requiredBackends)
    }

    /// 원본을 보존하되, required 에 없는 백엔드 줄은 주석 처리.
    /// net/escl(네트워크 프로브)은 특히 주석 처리.
    static func rewriteKeepingOnly(required: Set<String>, original: String) -> String {
        var out: [String] = []
        for raw in original.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // 빈 줄/이미 주석/주석 라인은 그대로.
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                out.append(line)
                continue
            }
            // 백엔드 이름 추출(첫 토큰).
            let name = trimmed.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? trimmed
            if required.contains(name) {
                out.append(line)   // 유지
            } else {
                out.append("# [negaflow] 비활성화: " + line)   // 주석 처리 + 출처 표시
            }
        }
        return out.joined(separator: "\n")
    }
}
