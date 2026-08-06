// Measures the Windows ICM half of the colorsync-icm-parity-v1 probe.
//
// The macOS half is a committed reference produced by ColorSync on a fixed OS.
// This test rebuilds the same input profile, pushes the same 16-bit integers
// through the same IcmRgb16Transform the scanner path uses, decodes the sRGB
// result to linear the same way scanner_to_working does, and reports how far
// the two colour management systems land apart.
//
// It is a measurement, not a pass/fail judgement on colour correctness. The
// only hard assertions are that the profile bytes reproduce exactly and that
// the transform runs, because a divergence measured against a different
// profile would prove nothing.

#include "colorsync_icm_parity_fixture.h"
#include "icm_rgb16_transform.h"
#include "negaflow/color/srgb_transfer.h"
#include "negaflow/core/build_info.h"
#include "synthetic_parity_icc_profile.h"

#include <Windows.h>
#include <bcrypt.h>

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
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

[[nodiscard]] std::string sha256_hex(const std::vector<std::uint8_t>& bytes) {
    BCRYPT_ALG_HANDLE algorithm{nullptr};
    if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0U) != 0) {
        return {};
    }
    std::vector<std::uint8_t> digest(32U, 0U);
    const NTSTATUS status = BCryptHash(
        algorithm,
        nullptr,
        0U,
        const_cast<PUCHAR>(bytes.data()),
        static_cast<ULONG>(bytes.size()),
        digest.data(),
        static_cast<ULONG>(digest.size()));
    BCryptCloseAlgorithmProvider(algorithm, 0U);
    if (status != 0) {
        return {};
    }
    std::ostringstream text;
    text << std::hex << std::setfill('0');
    for (const std::uint8_t byte : digest) {
        text << std::setw(2) << static_cast<unsigned>(byte);
    }
    return text.str();
}

struct Measurement final {
    std::string_view name;
    std::array<std::uint16_t, 3> source;
    std::array<float, 3> macos_linear;
    std::array<std::uint16_t, 3> icm_encoded;
    std::array<float, 3> icm_linear;
};

void write_json(const std::vector<Measurement>& rows, const std::string& path) {
    std::ofstream file{path, std::ios::binary | std::ios::trunc};
    if (!file) {
        std::cerr << "FAIL: cannot open " << path << " for the ICM measurement\n";
        ++failures;
        return;
    }
    file << std::setprecision(9);
    file << "{\n";
    file << "  \"schemaVersion\": 1,\n";
    file << "  \"fixtureId\": \"" << negaflow::fixtures::colorsync_icm_parity_fixture_id
         << "\",\n";
    file << "  \"side\": \"windows-icm\",\n";
    file << "  \"profileSha256\": \""
         << negaflow::fixtures::colorsync_icm_parity_profile_sha256 << "\",\n";
    const negaflow::core::BuildInfo build = negaflow::core::query_build_info();
    file << "  \"sourceCommit\": \"" << build.source_commit << "\",\n";
    file << "  \"sourceDirty\": " << (build.source_dirty ? "true" : "false") << ",\n";
    file << "  \"architecture\": \""
         << negaflow::core::architecture_name(build.architecture) << "\",\n";
    file << "  \"colorManagement\": \"Windows ICM (mscms) CreateMultiProfileTransform, "
            "BEST_MODE\",\n";
    file << "  \"renderingIntent\": \"INTENT_RELATIVE_COLORIMETRIC\",\n";
    file << "  \"blackPointCompensation\": false,\n";
    file << "  \"intermediateEncoding\": \"16-bit sRGB integer\",\n";
    file << "  \"outputDomain\": \"linear-sRGB float\",\n";
    file << "  \"patches\": [\n";
    for (std::size_t index = 0U; index < rows.size(); ++index) {
        const Measurement& row = rows[index];
        file << "    {\"name\": \"" << row.name << "\", \"source\": ["
             << row.source[0] << ", " << row.source[1] << ", " << row.source[2]
             << "], \"icmEncoded\": [" << row.icm_encoded[0] << ", " << row.icm_encoded[1]
             << ", " << row.icm_encoded[2] << "], \"icmLinear\": [" << row.icm_linear[0]
             << ", " << row.icm_linear[1] << ", " << row.icm_linear[2] << "]}";
        file << (index + 1U == rows.size() ? "\n" : ",\n");
    }
    file << "  ]\n";
    file << "}\n";
}

}  // namespace

int main() {
    const std::vector<std::uint8_t> profile =
        negaflow::fixtures::build_synthetic_parity_profile();
    expect(
        profile.size() == negaflow::fixtures::colorsync_icm_parity_profile_bytes,
        "rebuilt parity profile has the recorded byte count");
    const std::string digest = sha256_hex(profile);
    expect(
        digest == negaflow::fixtures::colorsync_icm_parity_profile_sha256,
        "rebuilt parity profile hashes to the recorded SHA-256");
    if (failures != 0) {
        std::cerr << "rebuilt profile sha256 " << digest << "\n  expected            "
                  << negaflow::fixtures::colorsync_icm_parity_profile_sha256 << '\n';
        std::cerr << "refusing to compare: the two systems would be reading different "
                     "profiles\n";
        return 1;
    }

    negaflow::imaging::detail::IcmRgb16Transform transform{};
    std::uint32_t native_error = 0U;
    const auto initialize_status = transform.initialize(profile, native_error);
    expect(
        initialize_status == negaflow::imaging::ScannerToWorkingStatus::ok,
        "ICM accepts the synthetic scanner profile");
    if (initialize_status != negaflow::imaging::ScannerToWorkingStatus::ok) {
        std::cerr << "ICM initialize failed, native error " << native_error << '\n';
        return 1;
    }

    const auto& patches = negaflow::fixtures::colorsync_icm_parity_patches;
    const auto patch_count = static_cast<std::uint32_t>(patches.size());
    std::vector<std::uint16_t> source(static_cast<std::size_t>(patch_count) * 3U, 0U);
    for (std::size_t index = 0U; index < patches.size(); ++index) {
        source[index * 3U] = patches[index].source[0];
        source[index * 3U + 1U] = patches[index].source[1];
        source[index * 3U + 2U] = patches[index].source[2];
    }
    std::vector<std::uint16_t> destination(source.size(), 0U);
    const auto stride = static_cast<std::uint32_t>(patch_count * 3U * sizeof(std::uint16_t));
    const auto translate_status = transform.translate(
        source.data(), patch_count, 1U, stride, destination.data(), stride, native_error);
    expect(
        translate_status == negaflow::imaging::ScannerToWorkingStatus::ok,
        "ICM translates the parity patch row");
    if (translate_status != negaflow::imaging::ScannerToWorkingStatus::ok) {
        std::cerr << "ICM translate failed, native error " << native_error << '\n';
        return 1;
    }

    constexpr float u16_scale = 1.0F / 65'535.0F;
    std::vector<Measurement> rows;
    rows.reserve(patches.size());
    for (std::size_t index = 0U; index < patches.size(); ++index) {
        Measurement row{};
        row.name = patches[index].name;
        row.source = patches[index].source;
        row.macos_linear = patches[index].macos_linear;
        for (std::size_t channel = 0U; channel < 3U; ++channel) {
            const std::uint16_t encoded = destination[index * 3U + channel];
            row.icm_encoded[channel] = encoded;
            row.icm_linear[channel] = negaflow::color::srgb_encoded_to_linear(
                static_cast<float>(encoded) * u16_scale);
        }
        rows.push_back(row);
    }

    std::cout << "colorsync-icm-parity-v1  (macOS reference: "
              << negaflow::fixtures::colorsync_icm_parity_operating_system << ")\n";
    std::cout << std::left << std::setw(22) << "patch" << std::right << std::setw(8) << "src"
              << std::setw(14) << "macOS" << std::setw(14) << "windows" << std::setw(11)
              << "ratio" << '\n';
    double worst_ratio = 1.0;
    std::string worst_patch;
    for (const Measurement& row : rows) {
        const float macos = row.macos_linear[0];
        const float windows = row.icm_linear[0];
        std::ostringstream ratio_text;
        if (macos > 0.0F && windows > 0.0F) {
            const double ratio = static_cast<double>(macos) / static_cast<double>(windows);
            ratio_text << std::fixed << std::setprecision(3) << ratio << "x";
            if (ratio > worst_ratio) {
                worst_ratio = ratio;
                worst_patch = std::string{row.name};
            }
        } else {
            ratio_text << "-";
        }
        std::cout << std::left << std::setw(22) << std::string{row.name} << std::right
                  << std::setw(8) << row.source[0] << std::setw(14) << std::scientific
                  << std::setprecision(4) << macos << std::setw(14) << windows
                  << std::setw(11) << ratio_text.str() << std::defaultfloat << '\n';
    }
    std::cout << "\nlargest macOS/Windows ratio: " << std::fixed << std::setprecision(2)
              << worst_ratio << "x at " << worst_patch << '\n';

    std::string output_path(MAX_PATH, '\0');
    const DWORD output_length = GetEnvironmentVariableA(
        "NEGAFLOW_ICM_PARITY_OUTPUT",
        output_path.data(),
        static_cast<DWORD>(output_path.size()));
    if (output_length > 0U && output_length < output_path.size()) {
        output_path.resize(output_length);
        write_json(rows, output_path);
        std::cout << "wrote ICM measurement to " << output_path << '\n';
    }

    if (failures != 0) {
        std::cerr << failures << " ColorSync/ICM parity test(s) failed\n";
        return 1;
    }
    std::cout << "ColorSync/ICM parity probe completed\n";
    return 0;
}
