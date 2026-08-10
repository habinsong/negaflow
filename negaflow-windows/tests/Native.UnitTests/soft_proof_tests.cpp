// Soft proof reads a destination profile and turns it into the affine the display
// boundary applies.
//
// The profiles here are synthesised, but not invented: the header fields, tag shapes and
// white points reproduce the profiles actually installed under
// C:\Windows\System32\spool\drivers\color, including the two whose ICC v2 `wtpt` declares
// D65 rather than the D50 PCS white. That case is the whole reason the resolver prefers
// the colorants, so it is pinned here rather than left to whatever a given machine has
// installed. The real files are read as well when present, but only as corroboration.

#include "negaflow/color/soft_proof.h"

#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

namespace {

int failures = 0;

void expect(const bool condition, const char* const message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        ++failures;
    }
}

void expect_near(
    const double actual,
    const double expected,
    const double tolerance,
    const char* const message) {
    if (!(std::abs(actual - expected) <= tolerance)) {
        std::cerr << "FAIL: " << message << " (expected " << expected << ", got " << actual
                  << ")\n";
        ++failures;
    }
}

void write_be_u32(
    std::vector<std::uint8_t>& bytes,
    const std::size_t offset,
    const std::uint32_t value) {
    bytes[offset] = static_cast<std::uint8_t>((value >> 24U) & 0xffU);
    bytes[offset + 1U] = static_cast<std::uint8_t>((value >> 16U) & 0xffU);
    bytes[offset + 2U] = static_cast<std::uint8_t>((value >> 8U) & 0xffU);
    bytes[offset + 3U] = static_cast<std::uint8_t>(value & 0xffU);
}

[[nodiscard]] std::uint32_t to_s15_fixed16(const double value) noexcept {
    return static_cast<std::uint32_t>(
        static_cast<std::int32_t>(std::lround(value * 65536.0)));
}

constexpr std::uint32_t signature_of(const char (&text)[5]) noexcept {
    return (static_cast<std::uint32_t>(static_cast<unsigned char>(text[0])) << 24U) |
           (static_cast<std::uint32_t>(static_cast<unsigned char>(text[1])) << 16U) |
           (static_cast<std::uint32_t>(static_cast<unsigned char>(text[2])) << 8U) |
           static_cast<std::uint32_t>(static_cast<unsigned char>(text[3]));
}

struct XyzTag final {
    std::uint32_t signature;
    double x;
    double y;
    double z;
};

// Builds a profile whose header and tag table match a real one: every XYZ tag becomes a
// 20-byte XYZType record, and every `other` signature becomes a minimal 12-byte body so
// its presence can be tested without modelling a curve or a LUT.
[[nodiscard]] std::vector<std::uint8_t> make_profile(
    const std::uint32_t data_color_space,
    const std::vector<XyzTag>& xyz_tags,
    const std::vector<std::uint32_t>& other_tags) {
    const std::size_t tag_count = xyz_tags.size() + other_tags.size();
    const std::size_t table_end = 132U + tag_count * 12U;
    const std::size_t xyz_bytes = 20U;
    const std::size_t other_bytes = 12U;
    std::vector<std::uint8_t> bytes(
        table_end + (xyz_tags.size() * xyz_bytes) + (other_tags.size() * other_bytes), 0U);

    write_be_u32(bytes, 0U, static_cast<std::uint32_t>(bytes.size()));
    write_be_u32(bytes, 8U, 0x02100000U);
    write_be_u32(bytes, 12U, signature_of("mntr"));
    write_be_u32(bytes, 16U, data_color_space);
    write_be_u32(bytes, 20U, signature_of("XYZ "));
    write_be_u32(bytes, 36U, signature_of("acsp"));
    write_be_u32(bytes, 128U, static_cast<std::uint32_t>(tag_count));

    std::size_t record = 132U;
    std::size_t body = table_end;
    for (const XyzTag& tag : xyz_tags) {
        write_be_u32(bytes, record, tag.signature);
        write_be_u32(bytes, record + 4U, static_cast<std::uint32_t>(body));
        write_be_u32(bytes, record + 8U, static_cast<std::uint32_t>(xyz_bytes));
        write_be_u32(bytes, body, signature_of("XYZ "));
        write_be_u32(bytes, body + 8U, to_s15_fixed16(tag.x));
        write_be_u32(bytes, body + 12U, to_s15_fixed16(tag.y));
        write_be_u32(bytes, body + 16U, to_s15_fixed16(tag.z));
        record += 12U;
        body += xyz_bytes;
    }
    for (const std::uint32_t signature : other_tags) {
        write_be_u32(bytes, record, signature);
        write_be_u32(bytes, record + 4U, static_cast<std::uint32_t>(body));
        write_be_u32(bytes, record + 8U, static_cast<std::uint32_t>(other_bytes));
        write_be_u32(bytes, body, signature_of("curv"));
        record += 12U;
        body += other_bytes;
    }
    return bytes;
}

const std::vector<std::uint32_t> matrix_trc_curves{
    signature_of("rTRC"),
    signature_of("gTRC"),
    signature_of("bTRC"),
};

// The installed sRGB and Adobe RGB profiles: ICC v2.1, matrix/TRC, `wtpt` holding the
// unadapted D65 media white while the colorants sum to D50.
[[nodiscard]] std::vector<std::uint8_t> make_v2_display_profile_declaring_d65() {
    return make_profile(
        signature_of("RGB "),
        {
            {signature_of("wtpt"), 0.950455, 1.0, 1.08905},
            {signature_of("bkpt"), 0.0, 0.0, 0.0},
            {signature_of("rXYZ"), 0.436066, 0.222488, 0.013916},
            {signature_of("gXYZ"), 0.385147, 0.716873, 0.097076},
            {signature_of("bXYZ"), 0.143066, 0.060608, 0.714096},
        },
        matrix_trc_curves);
}

[[nodiscard]] std::vector<std::uint8_t> read_installed_profile(const char* const name) {
    std::string path = "C:\\Windows\\System32\\spool\\drivers\\color\\";
    path += name;
    std::ifstream file(path, std::ios::binary);
    if (!file) {
        return {};
    }
    return std::vector<std::uint8_t>(
        std::istreambuf_iterator<char>(file),
        std::istreambuf_iterator<char>());
}

void check_display_profile_proofs_as_identity() {
    const auto profile = make_v2_display_profile_declaring_d65();
    expect(
        negaflow::color::is_rgb_output_profile(profile),
        "a matrix/TRC RGB profile is a usable proof destination");

    const auto media = negaflow::color::read_soft_proof_media(profile);
    expect(media.has_white, "the white point resolves");
    // Read literally the declared D65 would divide out to 1.32 on blue and clamp to the
    // 1.2 ceiling, tinting every proof. The colorants say D50, so it does not.
    expect_near(media.white.x, 0.9642, 0.0005, "resolved white is D50 X");
    expect_near(media.white.y, 1.0, 0.0005, "resolved white is D50 Y");
    expect_near(media.white.z, 0.8249, 0.0005, "resolved white is D50 Z");

    const auto paper = negaflow::color::soft_proof_paper(media);
    const auto transfer = negaflow::color::soft_proof_transfer(paper);
    // Exactly one, not nearly one. The colorants only sum to D50 as closely as the
    // profile's author rounded them, and a scale of 1.000006 still moves the odd pixel by
    // a code once it quantises to eight bits.
    for (std::size_t channel = 0U; channel < 3U; ++channel) {
        expect_near(paper.white[channel], 1.0, 0.0, "paper white is exactly neutral");
        expect_near(paper.black[channel], 0.0, 0.0, "black ink is exactly zero");
    }
    expect(transfer.is_identity(), "a display profile proofs as an exact identity");
}

// A paper only just outside the snapping tolerance still has to be treated as measured,
// or the threshold would quietly swallow a real one.
void check_a_barely_tinted_paper_survives() {
    const double tolerance = negaflow::color::soft_proof_neutral_tolerance;
    negaflow::color::SoftProofMedia media{};
    media.has_white = true;
    media.white = {
        negaflow::color::soft_proof_reference_d50.x,
        negaflow::color::soft_proof_reference_d50.y,
        negaflow::color::soft_proof_reference_d50.z * (1.0 - (tolerance * 4.0)),
    };
    const auto paper = negaflow::color::soft_proof_paper(media);
    expect(
        paper.white[2] < 1.0 && paper.white[0] == 1.0,
        "a paper just past the tolerance keeps its tint on the channel that has one");
    expect(
        !negaflow::color::soft_proof_transfer(paper).is_identity(),
        "and it does not collapse to an identity");
}

void check_press_profile_simulates_paper() {
    // ISOcoated_v2_eci: a CMYK LUT profile whose `wtpt` is the measured paper, dimmer and
    // yellower than the reference. Nothing here may normalise that away.
    const auto profile = make_profile(
        signature_of("CMYK"),
        {{signature_of("wtpt"), 0.84552, 0.876831, 0.747162}},
        {signature_of("A2B0"), signature_of("B2A0")});

    expect(
        !negaflow::color::is_rgb_output_profile(profile),
        "a CMYK press profile is refused as a proof destination");

    const auto media = negaflow::color::read_soft_proof_media(profile);
    expect(media.has_white, "the measured paper white survives");
    expect(!media.has_black, "no bkpt means no ink lift");
    expect_near(media.white.x, 0.84552, 0.0001, "paper white keeps its measured X");

    const auto paper = negaflow::color::soft_proof_paper(media);
    expect_near(paper.white[0], 0.876706, 0.001, "paper red is dimmed");
    expect_near(paper.white[1], 0.876831, 0.001, "paper green is dimmed");
    expect_near(paper.white[2], 0.905761, 0.001, "paper blue is dimmed least");
    expect(
        paper.white[2] > paper.white[0],
        "a warm paper reads as less blue absorption, which is the visible point");
}

void check_output_gate() {
    const auto lut_rgb = make_profile(
        signature_of("RGB "),
        {{signature_of("wtpt"), 0.9642, 1.0, 0.8249}},
        {signature_of("A2B0"), signature_of("B2A0")});
    expect(
        negaflow::color::is_rgb_output_profile(lut_rgb),
        "an RGB LUT profile with B2A0 can be rendered into");

    const auto scanner = make_profile(
        signature_of("RGB "),
        {{signature_of("wtpt"), 0.9642, 1.0, 0.8249}},
        {signature_of("A2B0")});
    expect(
        !negaflow::color::is_rgb_output_profile(scanner),
        "an input profile with only A2B0 cannot be rendered into");

    const std::vector<std::uint8_t> malformed(64U, 0U);
    expect(
        !negaflow::color::is_rgb_output_profile(malformed),
        "a malformed profile is refused");
    expect(
        negaflow::color::read_soft_proof_media(malformed).empty(),
        "a malformed profile yields no media");
    expect(
        negaflow::color::read_soft_proof_media({}).empty(),
        "an absent profile yields no media");
}

void check_limits() {
    const auto bright = make_profile(
        signature_of("RGB "),
        {
            {signature_of("wtpt"), 4.0, 4.0, 4.0},
            {signature_of("bkpt"), 2.0, 2.0, 2.0},
        },
        {signature_of("B2A0")});
    const auto paper = negaflow::color::soft_proof_paper(
        negaflow::color::read_soft_proof_media(bright));
    for (std::size_t channel = 0U; channel < 3U; ++channel) {
        expect_near(paper.white[channel], 1.2, 1.0e-9, "paper white stops at its ceiling");
        expect_near(paper.black[channel], 0.3, 1.0e-9, "black ink stops at its ceiling");
    }
    const auto transfer = negaflow::color::soft_proof_transfer(paper);
    for (std::size_t channel = 0U; channel < 3U; ++channel) {
        expect_near(transfer.scale[channel], 0.9, 1.0e-6, "scale is the range that is left");
        expect_near(transfer.bias[channel], 0.3, 1.0e-6, "bias is the ink");
    }

    // Ink darker than paper would invert the frame. The range collapses instead.
    negaflow::color::SoftProofPaper inverted{};
    inverted.white = {0.1, 0.1, 0.1};
    inverted.black = {0.3, 0.3, 0.3};
    const auto collapsed = negaflow::color::soft_proof_transfer(inverted);
    for (std::size_t channel = 0U; channel < 3U; ++channel) {
        expect_near(collapsed.scale[channel], 0.0, 1.0e-9, "scale never goes negative");
    }

    expect(
        negaflow::color::SoftProofTransfer{}.is_identity(),
        "the default transfer leaves the picture alone");
}

void check_installed_profiles_agree() {
    struct Case final {
        const char* name;
        bool expect_rgb_output;
    };
    const std::array<Case, 3U> cases{{
        {"sRGB Color Space Profile.icm", true},
        {"AdobeRGB1998.icc", true},
        {"ISOcoated_v2_eci.icc", false},
    }};
    for (const Case& entry : cases) {
        const auto bytes = read_installed_profile(entry.name);
        if (bytes.empty()) {
            std::cout << "skipped (not installed): " << entry.name << '\n';
            continue;
        }
        expect(
            negaflow::color::is_rgb_output_profile(bytes) == entry.expect_rgb_output,
            entry.name);
        const auto paper = negaflow::color::soft_proof_paper(
            negaflow::color::read_soft_proof_media(bytes));
        if (entry.expect_rgb_output) {
            for (std::size_t channel = 0U; channel < 3U; ++channel) {
                expect_near(
                    paper.white[channel],
                    1.0,
                    0.0,
                    "an installed display profile proofs as an exact identity");
            }
        } else {
            expect(
                paper.white[1] < 0.95,
                "an installed press profile simulates a dimmer paper");
        }
    }
}

}  // namespace

int main() {
    check_display_profile_proofs_as_identity();
    check_a_barely_tinted_paper_survives();
    check_press_profile_simulates_paper();
    check_output_gate();
    check_limits();
    check_installed_profiles_agree();

    if (failures != 0) {
        std::cerr << failures << " soft proof assertion(s) failed\n";
        return 1;
    }
    std::cout << "soft proof checks passed\n";
    return 0;
}
