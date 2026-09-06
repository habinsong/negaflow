import Foundation

extension InputGammaProfile {
    /// RGB 공통 TRC가 identity 또는 단일 power일 때만 수치로 표시합니다.
    static func recordedPower(_ data: Data) -> Double? {
        guard (try? linearizedData(data)) != nil else { return nil }
        func u32(_ at: Int) -> UInt32 { (0..<4).reduce(0) { ($0 << 8) | UInt32(data[at + $1]) } }
        var values: [Double] = []
        for index in 0..<Int(u32(128)) {
            let entry = 132 + index * 12
            guard [0x72545243, 0x67545243, 0x62545243].contains(u32(entry)) else { continue }
            let offset = Int(u32(entry + 4))
            let kind = u32(offset)
            let value: Double
            if kind == 0x63757276, u32(offset + 8) == 0 { value = 1 }
            else if kind == 0x63757276, u32(offset + 8) == 1 {
                value = Double(Int(data[offset + 12]) * 256 + Int(data[offset + 13])) / 256
            } else if kind == 0x70617261, data[offset + 8] == 0, data[offset + 9] == 0 {
                value = Double(Int32(bitPattern: u32(offset + 12))) / 65536
            } else { return nil }
            guard value.isFinite, value > 0 else { return nil }
            values.append(value)
        }
        guard values.count == 3, values.allSatisfy({ $0 == values[0] }) else { return nil }
        return values[0]
    }
}
