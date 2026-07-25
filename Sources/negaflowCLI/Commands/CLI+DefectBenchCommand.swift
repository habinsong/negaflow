import Foundation
import Chromabase

// negaflow defect-bench — GrainMend RGB 자동 골든셋 벤치마크.
//
//   negaflow defect-bench <이미지 파일 또는 디렉토리> [--out dir] [--sensitivity 0.7]
//                      [--crops 8] [--crop-size 256] [--reference-dir dir] [--metrics-only]
//
// 각 이미지에 자동 검출(가이드 영역 결함 제거와 동일 코어) → v2 복원을 돌리고
// before/after/diff/mask PNG, 결함별 100% crop 스트립(before|after|diff),
// report.json/report.md(분류별 개수·confidence·변경 픽셀·시간)를 만든다.
// 화질 판정(QA)은 사람이 아티팩트를 보고 한다.
extension CLI {
    func defectBench() async throws {
        guard args.count > 2 else {
            fail("usage: negaflow defect-bench <image-or-dir> [--out dir] [--sensitivity 0.7] [--crops 8] [--crop-size 256] [--reference-dir dir] [--metrics-only]")
        }
        let input = URL(fileURLWithPath: args[2])
        var outDir = input.hasDirectoryPath
            ? input.appendingPathComponent("defect-bench")
            : input.deletingLastPathComponent().appendingPathComponent("defect-bench")
        var sensitivity = 0.7
        var crops = 8
        var cropSize = 256
        var referenceDirectory: URL?
        var metricsOnly = false
        var i = 3
        while i < args.count {
            if args[i] == "--out", i + 1 < args.count { outDir = URL(fileURLWithPath: args[i + 1]); i += 2 }
            else if args[i] == "--sensitivity", i + 1 < args.count { sensitivity = Double(args[i + 1]) ?? sensitivity; i += 2 }
            else if args[i] == "--crops", i + 1 < args.count { crops = Int(args[i + 1]) ?? crops; i += 2 }
            else if args[i] == "--crop-size", i + 1 < args.count { cropSize = Int(args[i + 1]) ?? cropSize; i += 2 }
            else if args[i] == "--reference-dir", i + 1 < args.count {
                referenceDirectory = URL(fileURLWithPath: args[i + 1]); i += 2
            }
            else if args[i] == "--metrics-only" { metricsOnly = true; i += 1 }
            else { i += 1 }
        }

        let inputs = try DefectBenchInputResolver.resolve(
            input: input,
            referenceDirectory: referenceDirectory
        )

        print("[defect-bench] \(inputs.count)개 이미지 → \(outDir.path) (sensitivity \(sensitivity))")
        var entries: [DefectBenchEntry] = []
        for input in inputs {
            print("[defect-bench] \(input.imageURL.lastPathComponent) ...")
            do {
                let entry = try autoreleasepool {
                    try DefectBenchRunner.run(imageURL: input.imageURL,
                                           referenceURL: input.referenceURL,
                                           outputDir: outDir,
                                           writeArtifacts: !metricsOnly,
                                           sensitivity: sensitivity, cropCount: crops, cropSize: cropSize)
                }
                entries.append(entry)
                let classes = entry.defectCounts.sorted { $0.key < $1.key }
                    .map { "\($0.key) \($0.value)" }.joined(separator: ", ")
                print(String(format: "  defects=%d (%@) conf=%.2f candidates=%.3f%% changed=%.3f%% safety=%@ detect=%.0fms repair=%.0fms",
                             entry.defectTotal, classes, entry.meanConfidence,
                             entry.candidatePixelFraction * 100,
                             entry.changedPixelFraction * 100,
                             entry.automaticFalsePositiveRisk ? "risk" : "ok",
                             entry.detectMilliseconds, entry.repairMilliseconds))
            } catch {
                FileHandle.standardError.write(Data("  실패: \(error)\n".utf8))
            }
        }
        guard !entries.isEmpty else { fail("모든 이미지 벤치 실패") }
        try DefectBenchRunner.writeReport(entries, to: outDir)
        print("[defect-bench] 완료 — \(outDir.appendingPathComponent("report.md").path)")
    }
}
