// Phase 0 검증 — ImageCaptureCore 장치 탐지 (Xcode 26 SDK 기준)
//
// Plustek OpticFilm 8200i가 ICDeviceBrowser에 나타나는지, ICScannerDevice로
// 접근 가능한지, 그리고 Xcode 26 SDK에서 어느 수준까지 capability가 열리는지
// 콘솔에 덤프한다.
//
// 빌드/실행:
//   cd Phase0/ICADetect && swift run
import Cocoa
import ImageCaptureCore

final class Detector: NSObject, ICDeviceBrowserDelegate, ICScannerDeviceDelegate {
    let browser = ICDeviceBrowser()
    var found = 0

    func run() {
        browser.delegate = self
        browser.browsedDeviceTypeMask = .scanner
        print("[ICA] starting browser (browsedDeviceTypeMask = .scanner)")
        browser.start()
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline, found == 0 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        print("[ICA] stop after \(found) device(s)")
        browser.stop()
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        found += 1
        print("────────────── DEVICE FOUND ──────────────")
        print("name           : \(device.name ?? "?")")
        print("type           : \(deviceTypeString(device))")
        print("isRemote       : \(device.isRemote)")
        print("hasOpenSession : \(device.hasOpenSession)")
        print("usbVendorID    : \(device.usbVendorID)")
        print("usbProductID   : \(device.usbProductID)")
        if let scanner = device as? ICScannerDevice {
            dumpScanner(scanner)
        }
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        print("[ICA] device removed: \(device.name ?? "?")")
    }

    // MARK: ICDeviceDelegate (필수)
    func didRemove(_ device: ICDevice) {
        print("[ICA] didRemove: \(device.name ?? "?")")
    }
    func device(_ device: ICDevice, didOpenSessionWithError error: (any Error)?) {
        if let error { print("[ICA] session open error: \(error.localizedDescription)") }
        else        { print("[ICA] session opened: \(device.name ?? "?")") }
    }
    func device(_ device: ICDevice, didCloseSessionWithError error: (any Error)?) {
        if let error { print("[ICA] session close error: \(error.localizedDescription)") }
        else        { print("[ICA] session closed: \(device.name ?? "?")") }
    }

    func dumpScanner(_ s: ICScannerDevice) {
        print("────────────── ICSCANNERDEVICE (Xcode 26 SDK) ───────────")
        // Xcode 26 SDK 기준 ICScannerDevice의 노출 프로퍼티는 극히 제한적이다.
        // 과거 API(scannerState/maxScanDefinition/supportedResolutions 등)는 Swift에 노출 X.
        print("availableFunctionalUnitTypes: \(s.availableFunctionalUnitTypes)")
        print("documentUTI      : \(s.documentUTI)")
        print("documentName     : \(s.documentName)")
        print("transferMode     : \(s.transferMode.rawValue)")
        let fu = s.selectedFunctionalUnit
        print("selectedFunctionalUnit class: \(String(describing: type(of: fu)))")
        print("  type               : \(fu.type.rawValue)")
        print("  pixelDataType      : \(fu.pixelDataType.rawValue)")
        print("  supportedBitDepths : \(fu.supportedBitDepths)")
        print("  bitDepth           : \(fu.bitDepth.rawValue)")
        print("  supportedResol.    : \(fu.supportedResolutions)")
        print("  supportedMeasure   : \(fu.supportedMeasurementUnits)")
        print("  nativeRes X/Y      : \(fu.nativeXResolution)/\(fu.nativeYResolution)")
        print("  physicalSize       : \(fu.physicalSize)")
        print("  canOverview        : \(fu.canPerformOverviewScan)")
        print("  templates          : \(fu.templates.count)")
        print("  vendorFeatures     : \(fu.vendorFeatures?.count ?? 0)")
    }

    func deviceTypeString(_ d: ICDevice) -> String {
        switch d.type {
        case .camera:  return "camera"
        case .scanner: return "scanner"
        default:       return "type(\(d.type.rawValue))"
        }
    }
}

@main
struct ICADetect {
    static func main() {
        // NSApplication 없이 메인 스레드 runloop만 돌린다. ICA delegate는
        // 메인 runloop에 예약되므로 이것만으로 충분하다.
        let det = Detector()
        det.run()
        // 1초 더 여유 후 종료
        RunLoop.current.run(until: Date().addingTimeInterval(1))
    }
}
