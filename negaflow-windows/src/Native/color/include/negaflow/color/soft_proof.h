#pragma once

#include <array>
#include <cstdint>
#include <span>

namespace negaflow::color {

// Soft proof reads the destination profile's media white and black ink and turns them
// into the affine the display boundary applies. It is a viewing simulation: it never
// touches a published artefact, and the develop recipe does not carry it.

struct SoftProofXyz final {
    double x{0.0};
    double y{0.0};
    double z{0.0};
};

struct SoftProofMedia final {
    bool has_white{false};
    SoftProofXyz white{};
    bool has_black{false};
    SoftProofXyz black{};

    [[nodiscard]] bool empty() const noexcept { return !has_white && !has_black; }
};

// Per-channel factors, not a colorimetric conversion: each XYZ component is divided by
// the matching D50 component. That is what macOS does and what the display boundary
// consumes, so the port keeps it rather than substituting a "more correct" XYZ->RGB.
struct SoftProofPaper final {
    std::array<double, 3> white{1.0, 1.0, 1.0};
    std::array<double, 3> black{0.0, 0.0, 0.0};
};

// out = in * scale + bias, applied per channel in linear light.
struct SoftProofTransfer final {
    std::array<float, 3> scale{1.0F, 1.0F, 1.0F};
    std::array<float, 3> bias{0.0F, 0.0F, 0.0F};

    [[nodiscard]] bool is_identity() const noexcept {
        return scale[0] == 1.0F && scale[1] == 1.0F && scale[2] == 1.0F &&
               bias[0] == 0.0F && bias[1] == 0.0F && bias[2] == 0.0F;
    }
};

inline constexpr SoftProofXyz soft_proof_reference_d50{0.9642, 1.0, 0.8249};

// Ceilings on how far the simulation may move the picture. Paper may read brighter than
// the reference white, but not without limit; ink may lift the black, but a bias above
// 0.3 would wash the frame out rather than show what the print will do.
inline constexpr double soft_proof_paper_white_ceiling = 1.2;
inline constexpr double soft_proof_black_ink_ceiling = 0.3;

// How close to the reference a media reading has to be before it counts as "this profile
// declares the reference white" rather than as a measured paper.
//
// It exists because the D50 white is reconstructed from the colorants, and a profile's
// colorants only sum to D50 as closely as their author rounded them - measured across the
// installed profiles, within 2e-4. Left unsnapped, a scale of 1.000006 still flips the
// odd pixel by one code at the 8-bit boundary, so a display profile would not quite
// reproduce the unproofed frame the way it does on macOS.
//
// A thousandth is two orders of magnitude below anything visible and two orders above the
// observed reconstruction spread. Real papers are nowhere near it: the press profile
// installed here reads 0.877, twelve percent away.
inline constexpr double soft_proof_neutral_tolerance = 1.0e-3;

// Reads `wtpt` and `bkpt` from a validated ICC profile.
//
// One deliberate difference from macOS. There the profile arrives through
// CGColorSpace, which re-serialises it, so `wtpt` is already the D50 PCS white; here the
// file is read as it sits on disk, and an ICC v2 matrix/TRC profile is free to store the
// unadapted media white instead. The Windows system sRGB and Adobe RGB profiles both do
// (they carry D65), which under the literal rule would tint every proof blue.
//
// So for a matrix/TRC RGB profile the D50-relative white is taken from the colorants,
// which sum to the PCS white by construction. Measured on the installed profiles the sum
// lands within 2e-4 of D50 even for the two that declare D65, giving the identity proof
// macOS gets from its built-ins. LUT profiles - which is every real printer and press
// profile - are read straight from `wtpt`, so the measured paper white that makes the
// simulation worth anything survives untouched.
[[nodiscard]] SoftProofMedia read_soft_proof_media(
    std::span<const std::uint8_t> bytes) noexcept;

// Whether the profile can serve as a proof destination: a valid RGB profile carrying the
// tags needed to convert into it. macOS shares one gate between choosing a profile and
// restoring the choice, so a profile that cannot render never reaches the pixel path.
[[nodiscard]] bool is_rgb_output_profile(std::span<const std::uint8_t> bytes) noexcept;

[[nodiscard]] SoftProofPaper soft_proof_paper(const SoftProofMedia& media) noexcept;

[[nodiscard]] SoftProofTransfer soft_proof_transfer(const SoftProofPaper& paper) noexcept;

}  // namespace negaflow::color
