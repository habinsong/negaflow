import Foundation
import ScannerKit

// MARK: - negaflow CLI
//
// Phase 0/1/2를 한 명령으로 엮어 end-to-end 검증하는 도구.
//
//   negaflow detect                          → 스캐너 감지
//   negaflow capabilities <scannerID>        → capability 덤프
//   negaflow scan [--dpi 3600] [--preview]   → 스캔 수행
//   negaflow develop <in.tiff> <out.jpg> [--look rich-neutral]
//   negaflow it8-bench <manifest.json>        → IT8 패치별 색차 측정
//   negaflow scanner-relative-it8-bench <reference.txt> --sha256 sha256:...
//                                             → NORITSU/FUJI 합성 네거티브 상대 회귀
//   negaflow report                          → Scanner Report JSON
//   negaflow selftest                        → 합성 네거티브 → 현상 자동 검증

struct CLI {
    let args: [String]
    let registry: ScannerRegistry
    let jsonMode: Bool

    init(args: [String]) {
        let demoEnabled = args.contains("--demo")
        self.jsonMode = args.contains("--json")
        self.args = args.filter { $0 != "--demo" && $0 != "--json" }
        self.registry = ScannerRegistry.default(includeDemo: demoEnabled)
    }

    func run() async {
        let cmd = args.count > 1 ? args[1] : "help"
        if jsonMode && !Self.jsonCommands.contains(cmd) {
            fail("--json is supported only by detect and capabilities", code: "unsupported_json_command")
        }
        do {
            switch cmd {
            case "detect":       try await detect()
            case "capabilities": try await capabilities()
            case "scan":         try await scan()
            case "develop":      try await develop()
            case "list-scanner-profiles": listScannerProfiles()
            case "it8-bench":    try await it8Bench()
            case "scanner-relative-it8-bench": try await scannerRelativeIT8Bench()
            case "defect-bench":    try await defectBench()
            case "report":       try await report()
            case "selftest":     try await selftest()
            default:             printHelp()
            }
        } catch {
            if jsonMode {
                writeJSONError(code: "command_failed", message: String(describing: error), command: cmd)
            }
            FileHandle.standardError.write(Data("[negaflow] error: \(error)\n".utf8))
            exit(1)
        }
    }

    func fail(_ message: String, code: String = "invalid_arguments") -> Never {
        if jsonMode {
            let command = args.count > 1 ? args[1] : "help"
            writeJSONError(code: code, message: message, command: command)
        }
        FileHandle.standardError.write(Data("\(message)\n".utf8))
        exit(2)
    }
    func printHelp() {
        print("""
        negaflow — macOS-native film importing, scanning & developing
        commands:
          detect [--demo] [--json]       detect scanners; --demo explicitly adds Mock
          capabilities <scannerID> [--json]
                                         dump every reported capability
          scan [--dpi 3600] [--preview] [--positive] [--hdr] [--demo]
                                         run a scan
          develop <in> <out> [opts]      develop an image → JPEG/TIFF
          list-scanner-profiles          list bundled NORITSU/SP-3000 profiles
            --look <name>                none|neutral|rich-neutral|soft-print|clear-chrome|warm-lab|deep-slide
            --scanner-profile <id>       apply bundled scanner/film profile before look controls
            --film-type <T>              colorNegative|colorPositive|bwNegative|bwPositive
            --target <main|print>        develop target (default main)
            --output-icc <path>          required RGB printer ICC for target=print
            --output-icc-sha256 <hash>   required SHA-256 pin for target=print
            --positive                   shorthand for --film-type colorPositive
            --bw-positive                shorthand for --film-type bwPositive
            --exposure <stops>           Basic Tone exposure
            --contrast <v>               Basic Tone contrast (-1...1)
            --highlights <v>             Basic Tone highlights (-1...1)
            --shadows <v>                Basic Tone shadows (-1...1)
            --whites <v>                 Basic Tone whites (-2...2)
            --blacks <v>                 Basic Tone blacks (-2...2)
            --density <v>                Basic Tone density (-1...1)
            --defects [strength]             GrainMend RGB strength (0...1, default 1)
            --defect-mask <png>             write defect mask PNG
            --defect-overlay <png>          write red defect mask overlay PNG
            (input formats: tiff/jpeg/png/dng/raw/cr2/nef/...)
          defect-bench <image-or-dir>       GrainMend RGB automatic golden-set benchmark
            --out <dir>                  artifact directory (default: <input>/defect-bench)
            --sensitivity <0.7~6.0>      detection sensitivity (default 0.7)
            --crops <n>                  100% crop strips per image (default 8)
            --crop-size <px>             crop size (default 256)
          it8-bench <manifest.json>       measure every declared IT8 color patch
            --image <path>               local image override; manifest hash is still enforced
            --reference <path>           local reference override; manifest hash is still enforced
            --out <report.json>          patch-level Lab/CIEDE2000 report
          scanner-relative-it8-bench <reference.txt>
            --sha256 sha256:<hex>        pin the exact A1-L22 IT8 Lab reference bytes
            --out <report.json>          MAIN/NORITSU/FUJI patch-level relative report
          report [--demo]                export scanner report JSON without running scans
          selftest                       synthetic negative → develop (no hardware)
        """)
    }
}

await CLI(args: CommandLine.arguments).run()
