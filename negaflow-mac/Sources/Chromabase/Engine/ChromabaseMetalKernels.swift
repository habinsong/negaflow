import CoreImage

/// stitchable 커널 하나의 Metal 소스. 공용 헬퍼는 `prelude` 에 두고 여기에는 커널만 둔다.
struct MetalKernelSource {
    let name: String
    let body: String
}

// 커널마다 **독립 Metal 라이브러리**로 컴파일한다. 한 라이브러리에 든 stitchable 커널끼리는
// Core Image 가 융합 체인의 컴파일 프로그램을 같은 것으로 캐시해, 같은 자리에 다른 커널이 오면
// 앞서 컴파일된 커널의 코드를 새 인자로 실행한다. 2026-10-14 실측: 공유 CIContext 에서
// basicTone 체인 다음 parametricToneCurve 체인을 그리면 그래프 digest 는 다른데 프로그램 ID 가
// 같아 직전 결과가 나왔고, 최소 재현(kA/kB 두 커널)에서도 같은 라이브러리면 kB 체인이 kA 코드를
// 실행했다. 라이브러리를 나누면 프로그램 ID 가 갈리고, 커널 융합(단일 패스)은 그대로 유지된다.
//
// 컴파일은 커널을 처음 요청할 때 한 번만 한다. 33 개를 한꺼번에 컴파일하면 첫 현상이 단일
// 라이브러리 시절보다 약 15ms 늦어지므로, 실제로 쓰는 커널만 컴파일해 시작 비용을 맞춘다.
enum ChromabaseMetalKernels {
    private final class Registry: @unchecked Sendable {
        let lock = NSLock()
        var compiled: [String: CIKernel?] = [:]
    }
    private static let registry = Registry()

    private static let sourcesByName: [String: MetalKernelSource] = Dictionary(
        uniqueKeysWithValues: allKernelSources.map { ($0.name, $0) }
    )

    static var allKernelSources: [MetalKernelSource] {
        toneKernelSources + filterKernelSources + digitalKernelSources + detailKernelSources
    }

    static func colorKernel(named name: String) -> CIColorKernel? {
        kernel(named: name) as? CIColorKernel
    }

    /// 모든 커널을 컴파일해 성공한 이름만 돌려준다(검증용).
    static var availableKernelNames: Set<String> {
        Set(allKernelSources.compactMap { kernel(named: $0.name)?.name })
    }

    private static func kernel(named name: String) -> CIKernel? {
        registry.lock.lock()
        defer { registry.lock.unlock() }
        if let cached = registry.compiled[name] { return cached }
        guard let source = sourcesByName[name] else { return nil }
        var kernel: CIKernel?
        do {
            kernel = try CIKernel.kernels(withMetalString: prelude + "\n" + source.body)
                .first { $0.name == name }
        } catch {
            assertionFailure("Failed to compile Chromabase Metal kernel \(name): \(error)")
        }
        registry.compiled[name] = .some(kernel)
        return kernel
    }
}
