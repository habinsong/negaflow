import SwiftUI
import AppKit
import Chromabase

func signedControlText(_ value: Double) -> String {
    abs(value) < 0.005 ? "0.00" : String(format: "%+.2f", value)
}

func sliderInputText(_ value: Double) -> String {
    abs(value) < 0.005 ? "0" : String(format: "%.2f", value)
}
