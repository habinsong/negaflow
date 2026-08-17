#include "negaflow/color/srgb_transfer.h"
#include "synthetic_wic_tiff.h"
#include <algorithm>
#include <cmath>
#include <fstream>
#include <iostream>
#include "develop_export_abi_test_support.h"

namespace negaflow::develop_export_abi_tests {

// Soft proof exists only on the preview. There is no export entry point that accepts one,
// which is the structural half of the guarantee; this covers the behavioural half.
void test_v23_soft_proof_preview() {
    const std::uint32_t width = 96U;
    const std::uint32_t height = 64U;
    const std::filesystem::path source =
        std::filesystem::temp_directory_path() / "negaflow_abi_v23_soft_proof.tif";

    const std::vector<std::uint8_t> source_bytes =
        negaflow::test_fixtures::make_uncompressed_rgb16_defect_tiff(width, height);
    expect(
        !source_bytes.empty() && write_file(source, source_bytes),
        "v23 synthetic TIFF is written");
    if (!std::filesystem::exists(source)) {
        return;
    }

    const std::wstring source_text = source.wstring();
    nf_develop_export_request_v21 request = make_request_v21(
        source_text.c_str(),
        L"unused.png",
        NF_BASE_ESTIMATION_MANUAL);
    request.v20.v19.v18.v17.film_polarity = NF_FILM_POLARITY_POSITIVE;

    const std::size_t pixel_bytes = static_cast<std::size_t>(width) * height * 4U;
    const auto render = [&](const nf_soft_proof_v1* const proof,
                            std::vector<std::uint8_t>& pixels) {
        pixels.assign(pixel_bytes, 0U);
        nf_develop_export_result_v3 result = make_result_v3();
        const nf_status_t status = nf_develop_preview_v23(
            &request,
            proof,
            width,
            height,
            pixels.data(),
            static_cast<std::uint32_t>(pixels.size()),
            nullptr,
            &result);
        return status == NF_STATUS_OK && result.succeeded == 1U;
    };

    // The v22 pixels are the reference. Every way of saying "no proof" has to reproduce
    // them byte for byte, or the affine is not an identity when it is switched off.
    std::vector<std::uint8_t> reference(pixel_bytes, 0U);
    nf_develop_export_result_v3 reference_result = make_result_v3();
    expect(
        nf_develop_preview_v22(
            &request,
            width,
            height,
            reference.data(),
            static_cast<std::uint32_t>(reference.size()),
            nullptr,
            &reference_result) == NF_STATUS_OK &&
            reference_result.succeeded == 1U,
        "the unproofed v22 preview renders");

    std::vector<std::uint8_t> pixels{};
    expect(render(nullptr, pixels), "v23 renders with a null soft proof");
    expect(pixels == reference, "a null soft proof reproduces the v22 preview exactly");

    nf_soft_proof_v1 disabled = make_soft_proof();
    expect(render(&disabled, pixels), "v23 renders with proofing switched off");
    expect(pixels == reference, "a disabled soft proof reproduces the v22 preview exactly");

    // Profile-only proofing selects the space the frame is shown in. It is not a change
    // to the values, so the pixels the engine hands back must not move.
    nf_soft_proof_v1 profile_only = make_soft_proof();
    profile_only.enabled = 1U;
    expect(render(&profile_only, pixels), "v23 renders in profile-only proofing");
    expect(
        pixels == reference,
        "profile-only proofing does not alter the rendered values");

    // A dim, warm paper, the shape a press profile has. The ink is heavier than any real
    // one: this frame never gets darker than code 103, so a realistic ink would put the
    // floor below everything in it and the bound would pass without being tested. The
    // three channels differ so a transposed channel cannot go unnoticed.
    constexpr float paper_white[3] = {0.877F, 0.877F, 0.906F};
    constexpr float black_ink[3] = {0.20F, 0.19F, 0.22F};
    nf_soft_proof_v1 paper = make_soft_proof();
    paper.enabled = 1U;
    paper.simulate_paper_and_black_ink = 1U;
    for (std::size_t channel = 0U; channel < 3U; ++channel) {
        paper.paper_white_rgb[channel] = paper_white[channel];
        paper.black_ink_rgb[channel] = black_ink[channel];
    }
    expect(render(&paper, pixels), "v23 renders the paper and ink simulation");
    expect(
        pixels != reference,
        "simulating paper and ink changes the picture");

    // The two claims the feature actually makes: a print cannot be brighter than its
    // paper, and it cannot be darker than its ink. Both bounds are computed through the
    // same encode the preview quantises in, with one code of slack for the dither.
    const auto encoded_code = [](const float linear) {
        return negaflow::color::linear_to_srgb_encoded(linear) * 255.0F;
    };
    // Guard against a vacuous pass: the bounds only mean something if the unproofed frame
    // actually reaches outside them.
    std::uint8_t reference_low = 0xFFU;
    std::uint8_t reference_high = 0U;
    for (std::size_t offset = 0U; offset < reference.size(); offset += 4U) {
        for (std::size_t slot = 0U; slot < 3U; ++slot) {
            reference_low = std::min(reference_low, reference[offset + slot]);
            reference_high = std::max(reference_high, reference[offset + slot]);
        }
    }
    expect(
        static_cast<float>(reference_low) < encoded_code(black_ink[1]),
        "the unproofed frame goes darker than the ink, so the floor is a real bound");
    expect(
        static_cast<float>(reference_high) > encoded_code(paper_white[1]),
        "the unproofed frame goes brighter than the paper, so the ceiling is a real bound");

    bool within_paper = true;
    bool above_ink = true;
    bool opaque = true;
    // BGRA, so buffer slot 0 is blue and slot 2 is red.
    const std::size_t channel_of_slot[3] = {2U, 1U, 0U};
    for (std::size_t offset = 0U; offset < pixels.size(); offset += 4U) {
        for (std::size_t slot = 0U; slot < 3U; ++slot) {
            const std::size_t channel = channel_of_slot[slot];
            // A linear 1 maps to scale + bias, which is the paper white; a linear 0 maps
            // to the bias, which is the ink.
            const float ceiling = encoded_code(paper_white[channel]) + 1.5F;
            const float floor_value = encoded_code(black_ink[channel]) - 1.5F;
            const float value = static_cast<float>(pixels[offset + slot]);
            within_paper = within_paper && value <= ceiling;
            above_ink = above_ink && value >= floor_value;
        }
        opaque = opaque && pixels[offset + 3U] == 0xFFU;
    }
    expect(within_paper, "no proofed pixel is brighter than the simulated paper");
    expect(above_ink, "no proofed pixel is darker than the simulated ink");
    expect(opaque, "the proofed preview stays opaque");

    // Under-declaring the struct would let the engine read past what the caller owns.
    nf_soft_proof_v1 short_proof = make_soft_proof();
    short_proof.struct_size = 8U;
    std::vector<std::uint8_t> ignored_pixels(pixel_bytes, 0U);
    nf_develop_export_result_v3 short_result = make_result_v3();
    expect(
        nf_develop_preview_v23(
            &request,
            &short_proof,
            width,
            height,
            ignored_pixels.data(),
            static_cast<std::uint32_t>(ignored_pixels.size()),
            nullptr,
            &short_result) == NF_STATUS_STRUCT_TOO_SMALL,
        "an undersized soft proof struct is refused");

    std::error_code ignored;
    std::filesystem::remove(source, ignored);
}

void test_read_soft_proof_media() {
    nf_soft_proof_media_v1 media{};
    media.struct_size = static_cast<std::uint32_t>(sizeof(media));
    expect(
        nf_read_soft_proof_media_v1(nullptr, 0U, nullptr) == NF_STATUS_INVALID_ARGUMENT,
        "a null result is refused");

    nf_soft_proof_media_v1 short_media{};
    short_media.struct_size = 8U;
    expect(
        nf_read_soft_proof_media_v1(nullptr, 0U, &short_media) ==
            NF_STATUS_STRUCT_TOO_SMALL,
        "an undersized media struct is refused");

    // No profile at all is a legitimate state - proofing simply has nothing to simulate -
    // so it reports an unusable profile rather than failing the call.
    expect(
        nf_read_soft_proof_media_v1(nullptr, 0U, &media) == NF_STATUS_OK &&
            media.is_rgb_output_profile == 0U && media.has_white == 0U &&
            media.has_black == 0U,
        "an absent profile reads as unusable rather than as an error");

    const std::filesystem::path installed =
        "C:\\Windows\\System32\\spool\\drivers\\color\\sRGB Color Space Profile.icm";
    if (!std::filesystem::exists(installed)) {
        std::cout << "skipped (sRGB profile not installed)\n";
        return;
    }
    std::ifstream file(installed, std::ios::binary);
    std::istreambuf_iterator<char> first(file);
    const std::istreambuf_iterator<char> last{};
    const std::vector<std::uint8_t> bytes(first, last);
    media.struct_size = static_cast<std::uint32_t>(sizeof(media));
    expect(
        nf_read_soft_proof_media_v1(
            bytes.data(),
            static_cast<std::uint32_t>(bytes.size()),
            &media) == NF_STATUS_OK &&
            media.is_rgb_output_profile == 1U && media.has_white == 1U,
        "the installed sRGB profile is a usable proof destination");
    for (std::size_t channel = 0U; channel < 3U; ++channel) {
        expect(
            std::abs(media.paper_white_rgb[channel] - 1.0F) < 0.002F,
            "a display profile proofs as identity across the boundary");
    }
}

void test_soft_proof_on_a_real_scan(const std::filesystem::path& source) {
    const std::wstring source_text = source.wstring();
    nf_develop_export_request_v21 request = make_request_v21(
        source_text.c_str(),
        L"unused.png",
        NF_BASE_ESTIMATION_AUTO);

    const std::uint32_t extent = 512U;
    const std::size_t pixel_bytes = static_cast<std::size_t>(extent) * extent * 4U;
    std::vector<std::uint8_t> reference(pixel_bytes, 0U);
    nf_develop_export_result_v3 reference_result = make_result_v3();
    if (nf_develop_preview_v23(
            &request,
            nullptr,
            extent,
            extent,
            reference.data(),
            static_cast<std::uint32_t>(reference.size()),
            nullptr,
            &reference_result) != NF_STATUS_OK ||
        reference_result.succeeded != 1U) {
        expect(false, "the real scan renders an unproofed preview");
        return;
    }

    const char* const installed[] = {
        "sRGB Color Space Profile.icm",
        "AdobeRGB1998.icc",
        "eciRGB_v2.icc",
        "WideGamutRGB.icc",
    };
    std::size_t checked_profiles = 0U;
    std::vector<std::uint8_t> proofed(pixel_bytes, 0U);
    for (const char* const name : installed) {
        std::filesystem::path path =
            "C:\\Windows\\System32\\spool\\drivers\\color";
        path /= name;
        if (!std::filesystem::exists(path)) {
            continue;
        }
        std::ifstream file(path, std::ios::binary);
        std::istreambuf_iterator<char> first(file);
        const std::istreambuf_iterator<char> last{};
        const std::vector<std::uint8_t> bytes(first, last);

        nf_soft_proof_media_v1 media{};
        media.struct_size = static_cast<std::uint32_t>(sizeof(media));
        if (nf_read_soft_proof_media_v1(
                bytes.data(),
                static_cast<std::uint32_t>(bytes.size()),
                &media) != NF_STATUS_OK ||
            media.is_rgb_output_profile != 1U) {
            expect(false, name);
            continue;
        }

        nf_soft_proof_v1 proof = make_soft_proof();
        proof.enabled = 1U;
        proof.simulate_paper_and_black_ink = 1U;
        for (std::size_t channel = 0U; channel < 3U; ++channel) {
            proof.paper_white_rgb[channel] = media.paper_white_rgb[channel];
            proof.black_ink_rgb[channel] = media.black_ink_rgb[channel];
        }

        proofed.assign(pixel_bytes, 0U);
        nf_develop_export_result_v3 result = make_result_v3();
        const bool rendered =
            nf_develop_preview_v23(
                &request,
                &proof,
                extent,
                extent,
                proofed.data(),
                static_cast<std::uint32_t>(proofed.size()),
                nullptr,
                &result) == NF_STATUS_OK &&
            result.succeeded == 1U;
        expect(rendered, "the real scan renders a proofed preview");
        if (!rendered) {
            continue;
        }

        std::uint32_t largest_difference = 0U;
        for (std::size_t index = 0U; index < proofed.size(); ++index) {
            const std::uint32_t difference = static_cast<std::uint32_t>(
                std::abs(static_cast<int>(proofed[index]) -
                         static_cast<int>(reference[index])));
            largest_difference = std::max(largest_difference, difference);
        }
        if (largest_difference != 0U) {
            std::cerr << "FAIL: " << name << " moved the frame by "
                      << largest_difference << " codes\n";
            ++failures;
        }
        // Reported rather than asserted. The affine runs unconditionally, so what matters
        // is that carrying it costs nothing worth measuring next to the sRGB encode it
        // sits beside; a threshold here would only fail on a busy machine.
        std::cout << name << ": unproofed " << reference_result.wall_microseconds
                  << " us, proofed " << result.wall_microseconds << " us\n";
        ++checked_profiles;
    }
    expect(
        checked_profiles != 0U,
        "at least one installed display profile was measured against the scan");
}

}  // namespace negaflow::develop_export_abi_tests
