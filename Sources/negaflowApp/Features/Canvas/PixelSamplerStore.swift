import SwiftUI
import Chromabase

struct PixelSamplerReadout: Equatable {
    let sourceCoordinate: PixelCoordinate
    let original: PixelColorReading?
    let working: PixelColorReading?
    let proof: PixelColorReading?
}

@MainActor
final class PixelSamplerStore: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var readout: PixelSamplerReadout?
    private var workingBaseByFrameID: [UUID: CGImage] = [:]

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled {
            readout = nil
            workingBaseByFrameID.removeAll()
        }
    }

    func setWorkingBase(_ image: CGImage?, for frameID: UUID) {
        workingBaseByFrameID[frameID] = image
    }

    func workingBase(for frameID: UUID) -> CGImage? {
        workingBaseByFrameID[frameID]
    }

    func update(_ readout: PixelSamplerReadout?) {
        self.readout = readout
    }

    func removeFrame(_ frameID: UUID) {
        workingBaseByFrameID.removeValue(forKey: frameID)
        readout = nil
    }
}
