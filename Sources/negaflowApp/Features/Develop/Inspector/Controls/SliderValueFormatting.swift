import SwiftUI
import AppKit
import Chromabase

func signedControlText(_ value: Double) -> String {
    abs(value) < 0.005 ? "0.00" : String(format: "%+.2f", value)
}

func sliderInputText(_ value: Double) -> String {
    abs(value) < 0.005 ? "0" : String(format: "%.2f", value)
}

/// 0...1 값을 퍼센트 표시로.
func percentControlText(_ value: Double) -> String {
    "\(Int((value * 100).rounded()))%"
}

func percentInputText(_ value: Double) -> String {
    String(format: "%.0f", value * 100)
}
