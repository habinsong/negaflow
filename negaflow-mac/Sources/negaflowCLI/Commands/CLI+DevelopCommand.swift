import Foundation
import Chromabase
import CoreImage
import CoreGraphics

extension CLI {
    func develop() async throws {
        let options: DevelopCommandOptions
        switch DevelopCommandOptions.parse(Array(args.dropFirst(2))) {
        case .failure(let error):
            fail(error.message)
        case .success(let parsed):
            options = parsed
        }
        let inURL = URL(fileURLWithPath: options.inputPath)
        let outURL = URL(fileURLWithPath: options.outputPath)
        let lookName = options.lookName
        let scannerProfileID = options.scannerProfileID
        let filmType = options.filmType
        let scannerRaw = options.scannerRaw
        let defects = options.defects
        let developTarget = options.developTarget
        let outputICCURL = options.outputICCPath.map { URL(fileURLWithPath: $0) }
        let expectedOutputICCSHA256 = options.expectedOutputICCSHA256
        let defectMaskURL = options.defectMaskPath.map { URL(fileURLWithPath: $0) }
        let defectOverlayURL = options.defectOverlayPath.map { URL(fileURLWithPath: $0) }
        try ExportDestinationSafety.validateDistinct(
            protectedSources: [inURL, outputICCURL].compactMap { $0 },
            outputURLs: [outURL, defectMaskURL, defectOverlayURL].compactMap { $0 }
        )
        let kind = ImageLoader.kind(of: inURL)
        let resolvedFilmType: FilmType = filmType ?? guessFilmType(inURL, kind: kind)

        let engine = ChromabaseEngine()
        let preset = lookName == "none" ? nil : PresetRegistry.load(named: lookName)
        let scannerProfile = scannerProfileID.flatMap { ScannerProfileRegistry.load(named: $0) }
        if scannerProfileID != nil && scannerProfile == nil {
            fail("unknown scanner profile: \(scannerProfileID ?? "")")
        }
        var params = DevelopParameters()
        params.filmType = resolvedFilmType
        params.developTarget = developTarget
        params.scannerProfileID = scannerProfile?.id
        options.applyToneOverrides(to: &params)
        if let p = preset { params = DevelopParameters(preset: p, overrides: params) }
        params.filmType = resolvedFilmType
        params.developTarget = developTarget
        params.scannerProfileID = scannerProfile?.id
        if defects > 0 { params.defectRemoval = min(max(defects, 0), 1) }

        let outputProfile: ICCOutputProfileSnapshot?
        if developTarget == .print {
            guard let outputICCURL,
                  let expectedOutputICCSHA256,
                  let data = try? Data(contentsOf: outputICCURL),
                  let profile = ICCOutputProfileSnapshot(
                      profileName: outputICCURL.deletingPathExtension().lastPathComponent,
                      iccProfileData: data,
                      expectedSHA256: expectedOutputICCSHA256
                  ) else {
                fail("--target print requires a valid RGB printer-class --output-icc matching --output-icc-sha256")
            }
            outputProfile = profile
        } else {
            outputProfile = nil
        }

        let base: FilmBase?
        if resolvedFilmType.requiresInversion, scannerRaw,
           let raw = engine.loadScannerImage(inURL) {
            base = engine.estimateFilmBase(in: raw, mode: .auto)
        } else if resolvedFilmType.requiresInversion {
            base = engine.estimateFilmBase(at: inURL, mode: .auto)
        } else {
            base = nil
        }
        if let b = base {
            print("[develop] film base (auto): \(String(format: "%.3f %.3f %.3f", b.rgb.x, b.rgb.y, b.rgb.z)) [\(b.source.rawValue)]")
        }
        let profileLabel = scannerProfile?.id ?? "none"
        let outputProfileLabel = outputProfile.map { "sha256:\($0.profileSHA256)" } ?? "none"
        print("[develop] input=\(kind) target=\(developTarget.rawValue) filmType=\(resolvedFilmType.rawValue) look=\(lookName) scannerProfile=\(profileLabel) outputProfile=\(outputProfileLabel) → \(outURL.lastPathComponent)")
        let format: ExportFormat
        switch outURL.pathExtension.lowercased() {
        case "tif", "tiff":
            format = .tiff16
        case "png":
            format = .png
        default:
            format = .jpeg
        }
        if scannerRaw {
            try engine.developScannerFile(
                input: inURL,
                output: outURL,
                format: format,
                base: base,
                params: params,
                outputProfile: outputProfile
            )
        } else {
            try engine.developFile(
                input: inURL,
                output: outURL,
                format: format,
                base: base,
                params: params,
                outputProfile: outputProfile
            )
        }
        print("[develop] → \(outURL.path)")
        if defectMaskURL != nil || defectOverlayURL != nil {
            try writeDefectDebugOutputs(
                input: inURL,
                scannerRaw: scannerRaw,
                engine: engine,
                base: base,
                params: params,
                maskURL: defectMaskURL,
                overlayURL: defectOverlayURL
            )
        }
    }

    func listScannerProfiles() {
        let profiles = ScannerProfileRegistry.loadAll()
        if profiles.isEmpty {
            print("No scanner profiles bundled.")
            return
        }
        for profile in profiles {
            let limited = profile.singleRollLimited ? " single-roll-limited" : ""
            print("\(profile.id)\t\(profile.scanner)\t\(profile.kind)\t\(profile.filmKey)\t\(profile.validationStatus.rawValue)\(limited)")
        }
    }

    func writeDefectDebugOutputs(input: URL,
                              scannerRaw: Bool,
                              engine: ChromabaseEngine,
                              base: FilmBase?,
                              params: DevelopParameters,
                              maskURL: URL?,
                              overlayURL: URL?) throws {
        let source = scannerRaw ? engine.loadScannerImage(input) : engine.loadImage(input)
        guard let source else { throw ChromabaseError.loadFailed(input.path) }
        var debugParams = params
        debugParams.defectRemoval = 0
        let developed = scannerRaw
            ? engine.developScanner(image: source, base: base, params: debugParams)
            : engine.develop(image: source, base: base, params: debugParams)
        let defectParameters = SoftwareDefectParameters(
            strength: max(params.defectRemoval, 1),
            dustSensitivity: 0.65,
            scratchSensitivity: 0.85,
            protectDetail: 0.85
        )
        let mask = SoftwareDefectRemoval.detectMask(in: developed, parameters: defectParameters)
        let context = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB) as Any,
        ])
        if let maskURL {
            try ExportEngine.write(mask, to: maskURL, format: .png, using: context)
            print("[develop] defect mask → \(maskURL.path)")
        }
        if let overlayURL {
            let overlay = SoftwareDefectRemoval.overlayMask(on: developed, mask: mask, opacity: 0.72)
            try ExportEngine.write(overlay, to: overlayURL, format: .png, using: context)
            print("[develop] defect overlay → \(overlayURL.path)")
        }
    }

    func guessFilmType(_ url: URL, kind: ImageLoader.InputKind) -> FilmType {
        let name = url.lastPathComponent.lowercased()
        if name.contains("positive") || name.contains("slide") { return .colorPositive }
        if kind == .rawDng { return .colorPositive }
        return .colorNegative
    }
}
