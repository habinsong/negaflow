import Foundation
import CoreGraphics
import ImageIO
import Chromabase

extension ExternalScannerBackend {
    struct ValidatedRawArtifact {
        let url: URL
        let width: Int
        let height: Int
        let bitsPerComponent: Int
        let colorSpaceModel: CGColorSpaceModel?
        let typeIdentifier: String?
    }

    func validatedRawResult(
        _ event: PluginScanEvent,
        expectedURL: URL,
        verifiedAppliedOptions: ScanOptions?
    ) throws -> ValidatedRawArtifact {
        guard let path = event.path else {
            throw failure(.ioFailure, "plugin scan 결과 경로 누락")
        }
        let normalizedPath = (path as NSString).standardizingPath
        let expectedPath = (expectedURL.path as NSString).standardizingPath
        guard normalizedPath == expectedPath else {
            throw failure(.ioFailure, "plugin scan 결과 경로 불일치")
        }
        let url = URL(fileURLWithPath: normalizedPath)

        let artifact = try validatedImageArtifact(at: url, label: "plugin scan 결과")
        guard let verifiedAppliedOptions else {
            // Protocol v1은 실제 적용 옵션과 결과 metadata를 증명하는 계약이 없다.
            return artifact
        }
        guard artifact.typeIdentifier == "public.tiff" else {
            throw failure(.ioFailure, "plugin protocol v2 artifact 형식이 TIFF가 아님")
        }
        guard let reportedWidth = event.width,
              let reportedHeight = event.height,
              reportedWidth > 0,
              reportedHeight > 0 else {
            throw failure(.ioFailure, "plugin protocol v2 result width/height 누락 또는 유효하지 않음")
        }
        guard reportedWidth == artifact.width,
              reportedHeight == artifact.height else {
            throw failure(.ioFailure, "plugin protocol v2 result/artifact 픽셀 크기 불일치")
        }
        guard artifact.bitsPerComponent == verifiedAppliedOptions.bitDepth.rawValue else {
            throw failure(.ioFailure, "plugin protocol v2 result/artifact bitDepth 불일치")
        }
        let expectedColorSpaceModel: CGColorSpaceModel
        switch verifiedAppliedOptions.colorMode {
        case .color:
            expectedColorSpaceModel = .rgb
        case .gray, .lineart, .infrared:
            expectedColorSpaceModel = .monochrome
        }
        guard artifact.colorSpaceModel == expectedColorSpaceModel else {
            throw failure(.ioFailure, "plugin protocol v2 appliedOptions/artifact colorMode 불일치")
        }
        return artifact
    }

    func validatedImageArtifact(
        at url: URL,
        label: String
    ) throws -> ValidatedRawArtifact {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        } catch {
            throw failure(.ioFailure, "\(label) 파일 없음")
        }
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw failure(.ioFailure, "\(label)가 regular file이 아님")
        }
        guard let fileSize = values.fileSize, fileSize > 0 else {
            throw failure(.ioFailure, "\(label) 파일이 비어 있음")
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else {
            throw failure(.ioFailure, "\(label) 이미지 메타데이터 해석 실패")
        }
        let typeIdentifier = CGImageSourceGetType(source) as String?
        let decodeOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let decoded = CGImageSourceCreateImageAtIndex(
            source,
            0,
            decodeOptions as CFDictionary
        ), decoded.width > 0, decoded.height > 0, decoded.bitsPerComponent > 0 else {
            throw failure(.ioFailure, "\(label) 이미지 decode 실패")
        }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 16,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary),
              thumbnail.width > 0, thumbnail.height > 0 else {
            throw failure(.ioFailure, "\(label) 이미지 decode 실패")
        }
        return ValidatedRawArtifact(
            url: url,
            width: decoded.width,
            height: decoded.height,
            bitsPerComponent: decoded.bitsPerComponent,
            colorSpaceModel: decoded.colorSpace?.model,
            typeIdentifier: typeIdentifier
        )
    }

    func isInsideStagingDirectory(_ url: URL, stagingDirectory: URL) -> Bool {
        let directoryPath = stagingDirectory.standardizedFileURL.resolvingSymlinksInPath().path
        let candidatePath = url.standardizedFileURL.resolvingSymlinksInPath().path
        return candidatePath.hasPrefix(directoryPath + "/")
    }

    func validatedInfraredResult(
        _ event: PluginScanEvent,
        requested: Bool,
        matching rawArtifact: ValidatedRawArtifact,
        stagingDirectory: URL,
        requiresStagedPath: Bool
    ) throws -> URL? {
        let infraredURL = event.irPath.map { URL(fileURLWithPath: $0) }
        if !requested {
            guard infraredURL == nil, event.hasInfrared != true else {
                throw failure(.ioFailure, "plugin IR 계약 위반: 요청하지 않은 IR 결과")
            }
            return nil
        }

        guard let infraredURL else {
            throw failure(.ioFailure, "plugin IR 계약 위반: 요청한 IR 결과 누락")
        }
        guard event.hasInfrared != false else {
            throw failure(.ioFailure, "plugin IR 계약 위반: IR 경로와 플래그 불일치")
        }
        if requiresStagedPath, !isInsideStagingDirectory(infraredURL, stagingDirectory: stagingDirectory) {
            throw failure(.ioFailure, "plugin IR 계약 위반: protocol v2 IR 결과가 staging 경로 밖에 있음")
        }
        let artifact = try validatedImageArtifact(at: infraredURL, label: "plugin IR 결과")
        guard artifact.width == rawArtifact.width, artifact.height == rawArtifact.height else {
            throw failure(.ioFailure, "plugin IR 계약 위반: RGB/IR 픽셀 크기 불일치")
        }
        return artifact.url
    }


}
