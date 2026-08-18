#pragma once

/* WIC TIFF 디코더 suite 가 공유하는 fixture 와 관찰자입니다. 어떤 파일을 만들지는
   synthetic_wic_tiff.h 가, 무엇을 검사할지는 각 suite 파일이 소유합니다. */

#include "negaflow/imageio/wic_tiff_decoder.h"

#include <Windows.h>

#include <cstdint>
#include <filesystem>
#include <span>
#include <stop_token>
#include <string>
#include <system_error>
#include <vector>

namespace wic_tiff_decoder_tests {

// 실패 개수는 suite 전체가 공유합니다.
extern int failures;

void expect(bool condition, const char* message);

class TempDirectory final {
public:
    TempDirectory() {
        path_ = std::filesystem::temp_directory_path() /
                (L"negaflow-wic-tests-" + std::to_wstring(GetCurrentProcessId()));
        std::error_code error{};
        std::filesystem::remove_all(path_, error);
        error.clear();
        std::filesystem::create_directories(path_, error);
        expect(!error, "temporary WIC test directory is created");
    }

    TempDirectory(const TempDirectory&) = delete;
    TempDirectory& operator=(const TempDirectory&) = delete;

    ~TempDirectory() {
        std::error_code error{};
        std::filesystem::remove_all(path_, error);
    }

    [[nodiscard]] const std::filesystem::path& path() const noexcept {
        return path_;
    }

private:
    std::filesystem::path path_{};
};

class RecordingProgress final
    : public negaflow::imageio::WicTiffDecodeProgressObserver {
public:
    explicit RecordingProgress(
        std::stop_source* const stop_source = nullptr,
        const std::uint32_t cancel_after_rows = 0U) noexcept
        : stop_source_(stop_source), cancel_after_rows_(cancel_after_rows) {}

    void report(const negaflow::imageio::WicTiffDecodeProgress progress) noexcept override {
        if (event_count_ < events_.size()) {
            events_[event_count_] = progress;
            ++event_count_;
        }
        if (stop_source_ != nullptr && progress.completed_rows >= cancel_after_rows_ &&
            progress.completed_rows < progress.total_rows) {
            stop_source_->request_stop();
        }
    }

    [[nodiscard]] std::size_t event_count() const noexcept {
        return event_count_;
    }

    [[nodiscard]] const negaflow::imageio::WicTiffDecodeProgress& event(
        const std::size_t index) const noexcept {
        return events_[index];
    }

private:
    std::array<negaflow::imageio::WicTiffDecodeProgress, 32> events_{};
    std::size_t event_count_{0};
    std::stop_source* stop_source_{nullptr};
    std::uint32_t cancel_after_rows_{0};
};

class CollectingRowSink final : public negaflow::imageio::WicTiffRowSink {
public:
    explicit CollectingRowSink(const bool reject_first_write = false) noexcept
        : reject_first_write_(reject_first_write) {}

    bool begin(const negaflow::imageio::WicTiffFrameView& frame) noexcept override {
        try {
            if (frame.width == 0U || frame.height == 0U ||
                frame.stride_bytes % sizeof(std::uint16_t) != 0U) {
                return false;
            }
            height_ = frame.height;
            stride_samples_ = frame.stride_bytes / sizeof(std::uint16_t);
            const std::uint64_t sample_count =
                static_cast<std::uint64_t>(stride_samples_) * height_;
            if (sample_count > std::numeric_limits<std::size_t>::max()) {
                return false;
            }
            samples_.assign(static_cast<std::size_t>(sample_count), 0U);
            icc_profile_.assign(frame.icc_profile.begin(), frame.icc_profile.end());
            active_ = true;
            return true;
        } catch (...) {
            return false;
        }
    }

    bool write(const negaflow::imageio::WicTiffRowChunk& rows) noexcept override {
        if (reject_first_write_ && next_row_ == 0U) {
            return false;
        }
        if (!active_ || rows.first_row != next_row_ || rows.row_count == 0U ||
            rows.first_row > height_ || rows.row_count > height_ - rows.first_row ||
            rows.stride_bytes / sizeof(std::uint16_t) != stride_samples_) {
            return false;
        }
        const std::size_t expected_samples =
            static_cast<std::size_t>(stride_samples_) * rows.row_count;
        if (rows.samples.size() != expected_samples) {
            return false;
        }
        const std::size_t destination =
            static_cast<std::size_t>(rows.first_row) * stride_samples_;
        std::copy(rows.samples.begin(), rows.samples.end(), samples_.begin() + destination);
        next_row_ += rows.row_count;
        return true;
    }

    void complete(const negaflow::imageio::WicTiffDecodeStatus status) noexcept override {
        ++terminal_count_;
        terminal_status_ = status;
        committed_ = status == negaflow::imageio::WicTiffDecodeStatus::ok &&
                     next_row_ == height_;
        active_ = false;
        if (!committed_) {
            std::vector<std::uint16_t>{}.swap(samples_);
            std::vector<std::uint8_t>{}.swap(icc_profile_);
        }
    }

    [[nodiscard]] const std::vector<std::uint16_t>& samples() const noexcept {
        return samples_;
    }

    [[nodiscard]] const std::vector<std::uint8_t>& icc_profile() const noexcept {
        return icc_profile_;
    }

    [[nodiscard]] std::uint32_t terminal_count() const noexcept {
        return terminal_count_;
    }

    [[nodiscard]] negaflow::imageio::WicTiffDecodeStatus terminal_status() const noexcept {
        return terminal_status_;
    }

    [[nodiscard]] bool committed() const noexcept {
        return committed_;
    }

private:
    std::uint32_t height_{0};
    std::uint32_t stride_samples_{0};
    std::uint32_t next_row_{0};
    std::uint32_t terminal_count_{0};
    negaflow::imageio::WicTiffDecodeStatus terminal_status_{
        negaflow::imageio::WicTiffDecodeStatus::invalid_argument};
    bool active_{false};
    bool committed_{false};
    bool reject_first_write_{false};
    std::vector<std::uint16_t> samples_{};
    std::vector<std::uint8_t> icc_profile_{};
};

void write_fixture(const std::filesystem::path& path, const std::vector<std::uint8_t>& bytes);

// LZW 경로: 정상 복호, 회색 동반본, 8비트 확장, 코드 폭 전이, 사전 한계, 깨진 스트림.
void test_valid_lzw(const std::filesystem::path& root);
void test_gray16_companion(const std::filesystem::path& root);
void test_eight_bit_widens_by_bit_replication(const std::filesystem::path& root);
void test_lzw_code_width_transition(const std::filesystem::path& root);
void test_lzw_dictionary_limit_and_forward_reference(const std::filesystem::path& root);
void test_malformed_lzw(const std::filesystem::path& root);
void test_semantically_invalid_lzw(const std::filesystem::path& root);

// 스트리밍 경로: 행 복사 진행·취소, Deflate 선검사, 화소 한계, 저장소 fixture.
void test_row_copy_progress_and_cancellation(const std::filesystem::path& root);
void test_deflate_preflight(const std::filesystem::path& root);
void test_decoded_byte_limit(const std::filesystem::path& root);
void test_repository_fixture(const std::filesystem::path& path);

}  // namespace wic_tiff_decoder_tests
