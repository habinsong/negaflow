import Foundation

struct DefectBenchInput {
    let imageURL: URL
    let referenceURL: URL?
}

enum DefectBenchInputResolverError: LocalizedError {
    case missingInput(String)
    case noImages(String)
    case missingReference(String)

    var errorDescription: String? {
        switch self {
        case .missingInput(let path): return "입력이 없습니다: \(path)"
        case .noImages(let path): return "벤치할 이미지가 없습니다: \(path)"
        case .missingReference(let name): return "골든셋 정답 이미지가 없습니다: \(name)"
        }
    }
}

enum DefectBenchInputResolver {
    private static let imageExtensions: Set<String> = [
        "tiff", "tif", "png", "jpg", "jpeg", "dng", "raw", "cr2", "cr3", "nef", "arw", "heic"
    ]

    static func resolve(input: URL, referenceDirectory: URL?) throws -> [DefectBenchInput] {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: input.path, isDirectory: &isDirectory) else {
            throw DefectBenchInputResolverError.missingInput(input.path)
        }

        let imageURLs: [URL]
        if isDirectory.boolValue {
            imageURLs = try fileManager.contentsOfDirectory(at: input, includingPropertiesForKeys: nil)
                .filter { imageExtensions.contains($0.pathExtension.lowercased()) }
                .filter { referenceDirectory == nil || !$0.deletingPathExtension().lastPathComponent.hasSuffix("_restored") }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } else {
            imageURLs = [input]
        }
        guard !imageURLs.isEmpty else {
            throw DefectBenchInputResolverError.noImages(input.path)
        }

        return try imageURLs.map { imageURL in
            guard let referenceDirectory else {
                return DefectBenchInput(imageURL: imageURL, referenceURL: nil)
            }
            let baseName = imageURL.deletingPathExtension().lastPathComponent
            let referenceName = "\(baseName)_restored.\(imageURL.pathExtension)"
            let referenceURL = referenceDirectory.appendingPathComponent(referenceName)
            guard fileManager.fileExists(atPath: referenceURL.path) else {
                throw DefectBenchInputResolverError.missingReference(referenceName)
            }
            return DefectBenchInput(imageURL: imageURL, referenceURL: referenceURL)
        }
    }
}
