import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(
        Data("usage: generate-app-icon.swift <source-png> <output-png>\n".utf8)
    )
    exit(2)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard let sourceImage = NSImage(contentsOf: sourceURL) else {
    FileHandle.standardError.write(Data("원본 앱 아이콘을 읽을 수 없습니다: \(sourceURL.path)\n".utf8))
    exit(1)
}

let size = 1024
var sourceRect = NSRect(origin: .zero, size: sourceImage.size)
guard let sourceCGImage = sourceImage.cgImage(forProposedRect: &sourceRect, context: nil, hints: nil) else {
    FileHandle.standardError.write(Data("원본 앱 아이콘 픽셀을 읽을 수 없습니다.\n".utf8))
    exit(1)
}

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: size * 4,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else {
    FileHandle.standardError.write(Data("불투명 앱 아이콘 버퍼를 만들 수 없습니다.\n".utf8))
    exit(1)
}

context.setFillColor(
    CGColor(
        colorSpace: colorSpace,
        components: [0.055, 0.059, 0.066, 1]
    )!
)
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
context.interpolationQuality = .high
context.draw(sourceCGImage, in: CGRect(x: 0, y: 0, width: size, height: size))

guard let outputImage = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
        outputURL as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
      ) else {
    FileHandle.standardError.write(Data("불투명 앱 아이콘 PNG 출력을 만들 수 없습니다.\n".utf8))
    exit(1)
}

CGImageDestinationAddImage(destination, outputImage, nil)
guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write(Data("앱 아이콘 PNG를 저장할 수 없습니다.\n".utf8))
    exit(1)
}
