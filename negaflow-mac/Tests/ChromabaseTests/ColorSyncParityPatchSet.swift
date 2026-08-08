import Foundation

// The 34 device-RGB probes both platforms push through their CMS. Values are encoded
// scanner-device values in 0...1; the emitter quantises them to 16-bit before handing
// them to the colour engine, which is the depth Windows ICM receives.
enum ColorSyncParityPatchSet {
    struct Patch {
        let name: String
        let rgb: (Double, Double, Double)
    }

    static let patches: [Patch] = nearBlack + neutralRamp + saturated + skinTones + shoulder

    /// Black point compensation shows up here first: a CMS that rescales the shadow end
    /// moves these five and leaves the rest of the ramp almost untouched.
    private static let nearBlack: [Patch] = [
        Patch(name: "near_black_000", rgb: (0.000, 0.000, 0.000)),
        Patch(name: "near_black_005", rgb: (0.005, 0.005, 0.005)),
        Patch(name: "near_black_010", rgb: (0.010, 0.010, 0.010)),
        Patch(name: "near_black_020", rgb: (0.020, 0.020, 0.020)),
        Patch(name: "near_black_050", rgb: (0.050, 0.050, 0.050)),
    ]

    private static let neutralRamp: [Patch] = (1...8).map { step in
        let value = Double(step) / 8.0
        return Patch(
            name: String(format: "neutral_ramp_%03d", Int((value * 1000).rounded())),
            rgb: (value, value, value)
        )
    }

    /// Full primaries and secondaries, then the same hues at half saturation. Half
    /// saturation raises every zero channel to 0.5 and keeps the maxima at 1.0.
    private static let saturated: [Patch] = [
        Patch(name: "red_full", rgb: (1.0, 0.0, 0.0)),
        Patch(name: "green_full", rgb: (0.0, 1.0, 0.0)),
        Patch(name: "blue_full", rgb: (0.0, 0.0, 1.0)),
        Patch(name: "cyan_full", rgb: (0.0, 1.0, 1.0)),
        Patch(name: "magenta_full", rgb: (1.0, 0.0, 1.0)),
        Patch(name: "yellow_full", rgb: (1.0, 1.0, 0.0)),
        Patch(name: "red_half_saturation", rgb: (1.0, 0.5, 0.5)),
        Patch(name: "green_half_saturation", rgb: (0.5, 1.0, 0.5)),
        Patch(name: "blue_half_saturation", rgb: (0.5, 0.5, 1.0)),
        Patch(name: "cyan_half_saturation", rgb: (0.5, 1.0, 1.0)),
        Patch(name: "magenta_half_saturation", rgb: (1.0, 0.5, 1.0)),
        Patch(name: "yellow_half_saturation", rgb: (1.0, 1.0, 0.5)),
    ]

    private static let skinTones: [Patch] = [
        Patch(name: "skin_light", rgb: (0.878, 0.749, 0.663)),
        Patch(name: "skin_medium", rgb: (0.769, 0.573, 0.451)),
        Patch(name: "skin_deep", rgb: (0.427, 0.278, 0.196)),
    ]

    /// Shoulder plus two chromatic shadows — a shadow rescale that spares the neutral
    /// axis can still tint these.
    private static let shoulder: [Patch] = [
        Patch(name: "highlight_950", rgb: (0.950, 0.950, 0.950)),
        Patch(name: "highlight_980", rgb: (0.980, 0.980, 0.980)),
        Patch(name: "shadow_red", rgb: (0.200, 0.020, 0.020)),
        Patch(name: "shadow_blue", rgb: (0.020, 0.030, 0.200)),
        Patch(name: "shadow_neutral_075", rgb: (0.075, 0.075, 0.075)),
        Patch(name: "shadow_chromatic_low", rgb: (0.010, 0.008, 0.012)),
    ]
}
