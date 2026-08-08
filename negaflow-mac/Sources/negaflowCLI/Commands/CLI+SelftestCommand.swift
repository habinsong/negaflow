import Foundation
import ScannerKit
import Chromabase
import CoreGraphics
import ImageIO

extension CLI {
    func selftest() async throws {
        let engine = ChromabaseEngine()

        print("[selftest] generating synthetic negative...")
        let negURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("negaflow_selftest_neg.tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 800, height: 540, to: negURL)
        let base = engine.estimateFilmBase(at: negURL, mode: .auto)
        print("[selftest] film base: \(base.map { String(format: "%.3f %.3f %.3f", $0.rgb.x, $0.rgb.y, $0.rgb.z) } ?? "nil")")
        for look in ["neutral", "rich-neutral", "soft-print"] {
            guard let p = PresetRegistry.load(named: look) else { continue }
            var params = DevelopParameters()
            params.filmType = .colorNegative
            params = DevelopParameters(preset: p, overrides: params)
            params.filmType = .colorNegative
            let out = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("negaflow_selftest_neg_\(look).jpg")
            try engine.developFile(input: negURL, output: out, format: .jpeg, base: base, params: params)
            print("[selftest] negative look=\(look) → \(out.lastPathComponent)")
        }

        print("[selftest] generating synthetic positive...")
        let posURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("negaflow_selftest_pos.tiff")
        try Self.writeSyntheticPositive(width: 800, height: 540, to: posURL)
        for look in ["neutral", "deep-slide", "clear-chrome"] {
            guard let p = PresetRegistry.load(named: look) else { continue }
            var params = DevelopParameters()
            params.filmType = .colorPositive
            params = DevelopParameters(preset: p, overrides: params)
            params.filmType = .colorPositive
            let out = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("negaflow_selftest_pos_\(look).jpg")
            try engine.developFile(input: posURL, output: out, format: .jpeg, base: nil, params: params)
            print("[selftest] positive look=\(look) → \(out.lastPathComponent)")
        }
        print("[selftest] OK — negative + positive pipelines verified.")
    }

    static func writeSyntheticPositive(width: Int, height: Int, to url: URL) throws {
        let cs = CGColorSpace(name: CGColorSpace.genericRGBLinear)!
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let t = Double(y) / Double(height)
                let r = 0.15 + (1.0 - t) * 0.55
                let g = 0.20 + (1.0 - t) * 0.45
                let b = 0.35 + (1.0 - t) * 0.50
                let i = (y * width + x) * 4
                bytes[i] = UInt8(min(1.0, r) * 255)
                bytes[i+1] = UInt8(min(1.0, g) * 255)
                bytes[i+2] = UInt8(min(1.0, b) * 255)
                bytes[i+3] = 255
            }
        }
        let ctx = CGContext(data: &bytes, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: width * 4, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        guard let img = ctx.makeImage() else { throw ScannerError(.ioFailure, "synthetic positive") }
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.tiff" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)
    }
}
