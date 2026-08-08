import Foundation

extension DefectBenchRunner {
    /// report.json + report.md 를 쓴다.
    public static func writeReport(_ entries: [DefectBenchEntry], to outputDir: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(entries).write(to: outputDir.appendingPathComponent("report.json"))

        var markdown = "# GrainMend RGB 자동 벤치마크\n\n"
        markdown += "| image | size | defects | classes | mean conf | candidates | changed px | safety | PSNR Δ | detect ms | repair ms |\n"
        markdown += "|---|---|---|---|---|---|---|---|---|---|---|\n"
        for entry in entries {
            let classes = entry.defectCounts
                .sorted { $0.key < $1.key }
                .map { "\($0.key):\($0.value)" }
                .joined(separator: " ")
            let psnrDelta = entry.referenceMetrics?.psnrDelta
                .map { String(format: "%+.3f dB", $0) } ?? "—"
            markdown += String(
                format: "| %@ | %d×%d | %d | %@ | %.2f | %.3f%% | %.3f%% | %@ | %@ | %.0f | %.0f |\n",
                entry.imageName, entry.width, entry.height, entry.defectTotal, classes,
                entry.meanConfidence, entry.candidatePixelFraction * 100,
                entry.changedPixelFraction * 100,
                entry.automaticFalsePositiveRisk ? "risk" : "ok", psnrDelta,
                entry.detectMilliseconds, entry.repairMilliseconds
            )
        }
        if entries.contains(where: { !$0.artifacts.isEmpty }) {
            markdown += "\n`artifacts`에 기록된 `-before/-after/-diff/-mask.png`와 "
            markdown += "`-crop*.png`를 수동 비교하세요.\n"
        } else {
            markdown += "\n이 보고서는 metrics-only 실행 결과이며 비교 PNG를 생성하지 않았습니다.\n"
        }
        try markdown.data(using: .utf8)!.write(to: outputDir.appendingPathComponent("report.md"))
    }
}
