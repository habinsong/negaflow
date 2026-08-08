import Foundation

public struct ColorTargetLab: Codable, Sendable, Equatable {
    public let l: Double
    public let a: Double
    public let b: Double

    public init(l: Double, a: Double, b: Double) {
        self.l = l
        self.a = a
        self.b = b
    }
}

public enum ColorTargetColorimetry {
    /// Converts CIELAB D50/2° to unclamped extended linear-light sRGB.
    ///
    /// No gamut mapping or endpoint clipping is applied. That is required by target
    /// measurements because an IT8 reference can legitimately map outside the sRGB cube.
    public static func labD50ToLinearSRGB(_ lab: ColorTargetLab) -> SIMD3<Double> {
        let fy = (lab.l + 16.0) / 116.0
        let fx = fy + lab.a / 500.0
        let fz = fy - lab.b / 200.0
        let d50White = SIMD3<Double>(0.964_22, 1.0, 0.825_21)
        let xyzD50 = SIMD3<Double>(
            inverseLabTransfer(fx) * d50White.x,
            inverseLabTransfer(fy) * d50White.y,
            inverseLabTransfer(fz) * d50White.z
        )

        // Bradford chromatic adaptation from CIE D50 to the sRGB D65 encoding white.
        let xyzD65 = SIMD3<Double>(
            0.955_576_6 * xyzD50.x - 0.023_039_3 * xyzD50.y + 0.063_163_6 * xyzD50.z,
            -0.028_289_5 * xyzD50.x + 1.009_941_6 * xyzD50.y + 0.021_007_7 * xyzD50.z,
            0.012_298_2 * xyzD50.x - 0.020_483_0 * xyzD50.y + 1.329_909_8 * xyzD50.z
        )

        return SIMD3<Double>(
            3.240_454_2 * xyzD65.x - 1.537_138_5 * xyzD65.y - 0.498_531_4 * xyzD65.z,
            -0.969_266_0 * xyzD65.x + 1.876_010_8 * xyzD65.y + 0.041_556_0 * xyzD65.z,
            0.055_643_4 * xyzD65.x - 0.204_025_9 * xyzD65.y + 1.057_225_2 * xyzD65.z
        )
    }

    /// Converts unclamped linear-light sRGB values from their D65 encoding white to CIELAB D50/2°.
    public static func linearSRGBToLabD50(_ rgb: SIMD3<Double>) -> ColorTargetLab {
        let xyzD65 = SIMD3<Double>(
            0.412_456_4 * rgb.x + 0.357_576_1 * rgb.y + 0.180_437_5 * rgb.z,
            0.212_672_9 * rgb.x + 0.715_152_2 * rgb.y + 0.072_175_0 * rgb.z,
            0.019_333_9 * rgb.x + 0.119_192_0 * rgb.y + 0.950_304_1 * rgb.z
        )

        // Bradford chromatic adaptation from the sRGB D65 white to CIE D50.
        let xyzD50 = SIMD3<Double>(
            1.047_811_2 * xyzD65.x + 0.022_886_6 * xyzD65.y - 0.050_127_0 * xyzD65.z,
            0.029_542_4 * xyzD65.x + 0.990_484_4 * xyzD65.y - 0.017_049_1 * xyzD65.z,
            -0.009_234_5 * xyzD65.x + 0.015_043_6 * xyzD65.y + 0.752_131_6 * xyzD65.z
        )

        let d50White = SIMD3<Double>(0.964_22, 1.0, 0.825_21)
        let fx = labTransfer(xyzD50.x / d50White.x)
        let fy = labTransfer(xyzD50.y / d50White.y)
        let fz = labTransfer(xyzD50.z / d50White.z)
        return ColorTargetLab(
            l: 116.0 * fy - 16.0,
            a: 500.0 * (fx - fy),
            b: 200.0 * (fy - fz)
        )
    }

    /// CIEDE2000 with the parametric factors fixed to one, as specified for reference conditions.
    public static func deltaE2000(_ first: ColorTargetLab, _ second: ColorTargetLab) -> Double {
        let c1 = hypot(first.a, first.b)
        let c2 = hypot(second.a, second.b)
        let meanC = (c1 + c2) / 2.0
        let meanC7 = pow(meanC, 7.0)
        let twentyFive7 = pow(25.0, 7.0)
        let g = 0.5 * (1.0 - sqrt(meanC7 / (meanC7 + twentyFive7)))

        let a1Prime = (1.0 + g) * first.a
        let a2Prime = (1.0 + g) * second.a
        let c1Prime = hypot(a1Prime, first.b)
        let c2Prime = hypot(a2Prime, second.b)
        let h1Prime = hueDegrees(a: a1Prime, b: first.b)
        let h2Prime = hueDegrees(a: a2Prime, b: second.b)

        let deltaLPrime = second.l - first.l
        let deltaCPrime = c2Prime - c1Prime
        let deltaHuePrime = hueDifferenceDegrees(
            first: h1Prime,
            second: h2Prime,
            firstChroma: c1Prime,
            secondChroma: c2Prime
        )
        let deltaHPrime = 2.0 * sqrt(c1Prime * c2Prime)
            * sin(degreesToRadians(deltaHuePrime / 2.0))

        let meanLPrime = (first.l + second.l) / 2.0
        let meanCPrime = (c1Prime + c2Prime) / 2.0
        let meanHPrime = meanHueDegrees(
            first: h1Prime,
            second: h2Prime,
            firstChroma: c1Prime,
            secondChroma: c2Prime
        )

        let t = 1.0
            - 0.17 * cos(degreesToRadians(meanHPrime - 30.0))
            + 0.24 * cos(degreesToRadians(2.0 * meanHPrime))
            + 0.32 * cos(degreesToRadians(3.0 * meanHPrime + 6.0))
            - 0.20 * cos(degreesToRadians(4.0 * meanHPrime - 63.0))
        let deltaTheta = 30.0 * exp(-pow((meanHPrime - 275.0) / 25.0, 2.0))
        let meanCPrime7 = pow(meanCPrime, 7.0)
        let rC = 2.0 * sqrt(meanCPrime7 / (meanCPrime7 + twentyFive7))
        let lightnessOffset = meanLPrime - 50.0
        let sL = 1.0 + 0.015 * lightnessOffset * lightnessOffset
            / sqrt(20.0 + lightnessOffset * lightnessOffset)
        let sC = 1.0 + 0.045 * meanCPrime
        let sH = 1.0 + 0.015 * meanCPrime * t
        let rT = -sin(degreesToRadians(2.0 * deltaTheta)) * rC

        let normalizedL = deltaLPrime / sL
        let normalizedC = deltaCPrime / sC
        let normalizedH = deltaHPrime / sH
        return sqrt(
            normalizedL * normalizedL
                + normalizedC * normalizedC
                + normalizedH * normalizedH
                + rT * normalizedC * normalizedH
        )
    }

    private static func labTransfer(_ value: Double) -> Double {
        let epsilon = 216.0 / 24_389.0
        let kappa = 24_389.0 / 27.0
        return value > epsilon
            ? cbrt(value)
            : (kappa * value + 16.0) / 116.0
    }

    private static func inverseLabTransfer(_ value: Double) -> Double {
        let delta = 6.0 / 29.0
        return value > delta
            ? value * value * value
            : 3.0 * delta * delta * (value - 4.0 / 29.0)
    }

    private static func hueDegrees(a: Double, b: Double) -> Double {
        if a == 0.0, b == 0.0 {
            return 0.0
        }
        let degrees = radiansToDegrees(atan2(b, a))
        return degrees >= 0.0 ? degrees : degrees + 360.0
    }

    private static func hueDifferenceDegrees(
        first: Double,
        second: Double,
        firstChroma: Double,
        secondChroma: Double
    ) -> Double {
        guard firstChroma * secondChroma != 0.0 else { return 0.0 }
        let difference = second - first
        if abs(difference) <= 180.0 {
            return difference
        }
        return difference > 180.0 ? difference - 360.0 : difference + 360.0
    }

    private static func meanHueDegrees(
        first: Double,
        second: Double,
        firstChroma: Double,
        secondChroma: Double
    ) -> Double {
        guard firstChroma * secondChroma != 0.0 else { return first + second }
        if abs(first - second) <= 180.0 {
            return (first + second) / 2.0
        }
        let sum = first + second
        return sum < 360.0 ? (sum + 360.0) / 2.0 : (sum - 360.0) / 2.0
    }

    private static func degreesToRadians(_ value: Double) -> Double {
        value * .pi / 180.0
    }

    private static func radiansToDegrees(_ value: Double) -> Double {
        value * 180.0 / .pi
    }
}
