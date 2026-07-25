import Foundation
import ScannerKit
import Chromabase

extension CLI {
    func detect() async throws {
        let all = try await registry.detectAll()
        if jsonMode {
            let payload = ScannerCLIDetectPayload(backends: all.map {
                ScannerCLIDetectedBackend(backend: $0.backend, devices: $0.devices)
            })
            try writeJSON(payload, command: "detect")
            return
        }
        if all.flatMap(\.devices).isEmpty {
            print("No scanners detected. Use --demo to opt in to the Mock backend.")
            print("Backends probed:")
            for (b, _) in all { print("  - \(b.rawValue)") }
            return
        }
        for (backend, devices) in all {
            guard !devices.isEmpty else { continue }
            print("via \(backend.rawValue):")
            for d in devices {
                print("  [\(d.id)]")
                print("    name  : \(d.displayName)")
                print("    model : \(d.model)  (\(d.verifiedBadge))")
            }
        }
    }

    func capabilities() async throws {
        guard args.count > 2 else { fail("usage: negaflow capabilities <scannerID>") }
        let id = args[2]
        guard let backend = registry.backend(for: id) else { fail("unknown scanner: \(id)") }
        let cap = try await backend.getCapabilities(scannerID: id)
        if jsonMode {
            try writeJSON(
                ScannerCLICapabilitiesPayload(
                    scannerID: id,
                    backend: backend.backendType,
                    capabilities: cap
                ),
                command: "capabilities"
            )
            return
        }
        printCapabilityText(ScannerCLICapabilitySnapshot(cap))
    }

    func scan() async throws {
        var dpi = 3600
        var preview = false
        var filmType: FilmType = .colorNegative
        var hdr = false
        var i = 2
        while i < args.count {
            let a = args[i]
            if a == "--preview" {
                preview = true
                dpi = 0
                i += 1
            } else if a == "--dpi", i + 1 < args.count {
                dpi = Int(args[i + 1]) ?? dpi
                i += 2
            } else if a.hasPrefix("--dpi=") {
                dpi = Int(a.split(separator: "=").last.map(String.init) ?? "") ?? dpi
                i += 1
            } else if a == "--positive" {
                filmType = .colorPositive
                i += 1
            } else if a == "--bw-positive" {
                filmType = .bwPositive
                i += 1
            } else if a == "--hdr" {
                hdr = true
                i += 1
            } else {
                i += 1
            }
        }
        let all = try await registry.detectAll()
        let device = all.flatMap(\.devices).first(where: { $0.backendType == .plugin })
            ?? all.flatMap(\.devices).first
        guard let device else { fail("no scanner detected") }
        let backend = registry.backend(for: device.id)!
        let label = dpi == 0 ? "preview" : "\(dpi)dpi"
        let multiSample = !preview && hdr
        let filmLabel = filmType.requiresInversion ? "" : "_positive"
        let hdrLabel = multiSample ? "_hdr" : ""
        let out = URL(fileURLWithPath: "scan_\(label)\(filmLabel)\(hdrLabel).tiff")
        var opts = preview
            ? ScanOptions.preview(scannerID: device.id, filmType: filmType)
            : ScanOptions.strongDefault(scannerID: device.id)
        opts.resolution = Resolution(dpi)
        opts.bitDepth = .sixteen
        opts.filmType = filmType
        opts.multiExposureEnabled = multiSample
        opts.temporaryOutputURL = out
        print("[scan] \(device.displayName) @ \(dpi == 0 ? "preview" : "\(dpi)dpi") film=\(filmType.rawValue) multiSample=\(multiSample ? "on" : "off") → \(out.lastPathComponent)")
        let progress: @Sendable (ScanProgress) -> Void = { Self.logProgress($0) }
        let result = preview
            ? try await backend.startPreviewScan(opts, progress: progress)
            : try await backend.startFullScan(opts, progress: progress)
        print("[scan] done \(result.width)×\(result.height), \(String(format: "%.1f", result.scanDuration))s, \(result.backendUsed.rawValue)")
        print("[scan] → \(result.rawFileURL.path)")
    }

    func report() async throws {
        let all = try await registry.detectAll()
        guard let device = all.flatMap(\.devices).first else { fail("no scanner detected") }
        let backend = registry.backend(for: device.id)!
        let cap = try await backend.getCapabilities(scannerID: device.id)
        let r = ScannerReport(descriptor: device, backend: backend.backendType,
                              backendAvailable: true, capabilities: cap)
        let outURL = URL(fileURLWithPath: "scanner_report_\(Int(Date().timeIntervalSince1970)).json")
        try r.write(to: outURL)
        print("[report] → \(outURL.path)")
    }

    static func logProgress(_ p: ScanProgress) {
        let pct = p.fraction.map { String(format: "%3.0f%%", $0 * 100) } ?? "···"
        print("  \(pct)  \(p.phase.rawValue)  \(p.message)")
    }
}
