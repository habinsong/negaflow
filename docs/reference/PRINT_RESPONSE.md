# Fixed print response

[Docs home](../README.md)

Where it lives:

- Swift: `PrintResponse` in `Sources/Chromabase/Film/NegativeInversion.swift`
- Metal: the `negativeInvert` kernel
- Pinning test:
  `NegativeInversionCalibrationTests.testPrintResponseDerivesFromPhotometricContract`

## The curve

A film characteristic curve explains exposure against density as a toe, a straight line, and a
shoulder. negaflow approximates the shoulder in the density domain with a stretched exponential
curve.

```math
\begin{aligned}
D &= \log_{10}\left(\frac{D_{\min}}{T}\right) \\
d &= \frac{D}{d_{\max}} \\
\log_{10}(P) &= y_{\mathrm{ceil}} - A \exp\left(-(r d)^s\right)
\end{aligned}
```

`A`, `r`, and `s` are short forms of `amplitude`, `rate`, and `shape` in the code. `d_{\max}` is
`dmaxNorm`.

- `D`: optical density with the film base removed
- `d`: that value divided by the density range in use
- `P`: linear output brightness

The curve rises across the whole range. For `d ≥ 0` the output lands inside
`[baseToe, ceiling)`. Values below zero, such as a backlight brighter than the base or the
perforation, are not clipped to zero. They carry on as finite positive numbers.

```math
y(-|d|) = 2\log_{10}(P_{\mathrm{toe}}) - y(|d|)
```

The inverse has a closed form too. It is used to build synthetic negatives and run round-trip
checks.

```math
d = \frac{\left[\ln\left(\frac{A}{y_{\mathrm{ceil}}-\log_{10}(P)}\right)\right]^{1/s}}{r}
```

## The four anchors

Curve coefficients are not stored. They are computed from these values.

| Anchor | Color | Black and white | What it is for |
|---|---:|---:|---|
| `P(0)` base black point | 0.001 | 0.0005 | Keeps it off 8-bit code 0 |
| `P(midFraction)` mid gray | 0.18 | 0.18 | 18% gray |
| `P(1)` white | 0.70 | 0.85 | Brightness of the densest area measured |
| `P(∞)` ceiling | 0.90 | 0.98 | Headroom for reflected light |

`midFraction` is `0.60D / 1.55D`, about `0.387`.

Computing the coefficients:

```math
\begin{aligned}
y_{\mathrm{ceil}} &= \log_{10}(P_{\mathrm{ceil}}) \\
A &= y_{\mathrm{ceil}} - \log_{10}(P_{\mathrm{toe}}) \\
r_X &= \ln\left(\frac{A}{y_{\mathrm{ceil}}-\log_{10}(X)}\right) \\
s &= \frac{\ln(r_{\mathrm{white}}/r_{\mathrm{mid}})}
          {\ln(1/f_{\mathrm{mid}})} \\
r &= r_{\mathrm{white}}^{1/s}
\end{aligned}
```

## Default density range

`normalRange` is not the film's physical maximum density. It is the range a normally exposed
scene uses. It mostly matters when the base could not be measured, or when scene contrast is
very low.

```math
\begin{aligned}
\operatorname{normalRange}(\mathrm{color}) &= 0.62 \times 2.5 = 1.55\,D \\
\operatorname{normalRange}(\mathrm{B\&W}) &= 0.62 \times 3.5 = 2.17\,D
\end{aligned}
```

- `0.62`: rough slope of the straight-line section on a C-41 characteristic curve
- Color `2.5`: about 7⅓ stops of diffuse luminance plus highlight headroom
- Black and white `3.5`: black and white printing practice of using a longer straight line
- `0.60D`: mid gray density of a normally exposed scene

`applySceneRanged` measures the density range the frame actually uses per channel instead of
taking this value.

## What changed in v4

The old approach used a function split into three sections plus fixed presets. v4 uses one
curve and four anchors. There are no section boundaries, and every value can be traced in the
code and the tests.

Against the old result:

- Color midtones and highlights, normalized density 0.3 to 1.1: within ±0.05 stop
- Color deep shadows, 0.1 to 0.2: about −0.2 stop
- Color base black point: about +0.25 stop
- Black and white: shadows about −0.4 stop, midtones about +0.1 stop
- The NORITSU/FUJI mid gray anchor at 0.18 stays

## Sources and scope

Toe, straight line, shoulder, and gamma come from published sensitometry. None of the curve
coefficients in that literature were copied. negaflow computes its own from the four anchors
above.

- [Sensitometry](https://en.wikipedia.org/wiki/Sensitometry)
- [Hurter–Driffield Characteristic Curve](https://studyguides.com/study-methods/overview/cmpanf83znm1201neitjb4waw)
- [RA-4 paper comparison](https://tinker.koraks.nl/photography/on-a-color-mission-comparing-two-ra4-color-papers/)

The contrast ranges known for RA-4 material are not used directly. The contrast of this curve
comes from the `shape` derived from the four anchors.
