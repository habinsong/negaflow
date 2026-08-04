#include "atomic_output_file.h"

#include <array>
#include <atomic>
#include <cstddef>
#include <cstring>
#include <limits>
#include <new>
#include <string>
#include <string_view>
#include <utility>

namespace negaflow::output::detail {
namespace {

class HandleStream final : public IStream {
public:
    explicit HandleStream(const HANDLE handle) noexcept : handle_(handle) {}
    HandleStream(const HandleStream&) = delete;
    HandleStream& operator=(const HandleStream&) = delete;

    HRESULT STDMETHODCALLTYPE QueryInterface(
        const IID& interface_id,
        void** const object) noexcept override {
        if (object == nullptr) {
            return E_POINTER;
        }
        *object = nullptr;
        if (IsEqualIID(interface_id, IID_IUnknown) != FALSE ||
            IsEqualIID(interface_id, IID_ISequentialStream) != FALSE ||
            IsEqualIID(interface_id, IID_IStream) != FALSE) {
            *object = static_cast<IStream*>(this);
            AddRef();
            return S_OK;
        }
        return E_NOINTERFACE;
    }

    ULONG STDMETHODCALLTYPE AddRef() noexcept override {
        return reference_count_.fetch_add(1U, std::memory_order_relaxed) + 1U;
    }

    ULONG STDMETHODCALLTYPE Release() noexcept override {
        const ULONG remaining =
            reference_count_.fetch_sub(1U, std::memory_order_acq_rel) - 1U;
        if (remaining == 0U) {
            delete this;
        }
        return remaining;
    }

    HRESULT STDMETHODCALLTYPE Read(
        void* const destination,
        const ULONG byte_count,
        ULONG* const bytes_read) noexcept override {
        if (bytes_read != nullptr) {
            *bytes_read = 0U;
        }
        if (destination == nullptr && byte_count != 0U) {
            return STG_E_INVALIDPOINTER;
        }
        DWORD actual = 0U;
        if (ReadFile(handle_, destination, byte_count, &actual, nullptr) == FALSE) {
            return HRESULT_FROM_WIN32(GetLastError());
        }
        if (bytes_read != nullptr) {
            *bytes_read = actual;
        }
        return actual == byte_count ? S_OK : S_FALSE;
    }

    HRESULT STDMETHODCALLTYPE Write(
        const void* const source,
        const ULONG byte_count,
        ULONG* const bytes_written) noexcept override {
        if (bytes_written != nullptr) {
            *bytes_written = 0U;
        }
        if (source == nullptr && byte_count != 0U) {
            return STG_E_INVALIDPOINTER;
        }
        const auto* cursor = static_cast<const std::byte*>(source);
        ULONG total = 0U;
        while (total < byte_count) {
            DWORD actual = 0U;
            if (WriteFile(
                    handle_,
                    cursor + total,
                    byte_count - total,
                    &actual,
                    nullptr) == FALSE) {
                if (bytes_written != nullptr) {
                    *bytes_written = total;
                }
                return HRESULT_FROM_WIN32(GetLastError());
            }
            if (actual == 0U) {
                if (bytes_written != nullptr) {
                    *bytes_written = total;
                }
                return STG_E_WRITEFAULT;
            }
            total += actual;
        }
        if (bytes_written != nullptr) {
            *bytes_written = total;
        }
        return S_OK;
    }

    HRESULT STDMETHODCALLTYPE Seek(
        const LARGE_INTEGER move,
        const DWORD origin,
        ULARGE_INTEGER* const new_position) noexcept override {
        DWORD method = 0U;
        switch (origin) {
            case STREAM_SEEK_SET:
                method = FILE_BEGIN;
                break;
            case STREAM_SEEK_CUR:
                method = FILE_CURRENT;
                break;
            case STREAM_SEEK_END:
                method = FILE_END;
                break;
            default:
                return STG_E_INVALIDFUNCTION;
        }
        LARGE_INTEGER actual{};
        if (SetFilePointerEx(handle_, move, &actual, method) == FALSE) {
            return HRESULT_FROM_WIN32(GetLastError());
        }
        if (new_position != nullptr) {
            new_position->QuadPart = static_cast<ULONGLONG>(actual.QuadPart);
        }
        return S_OK;
    }

    HRESULT STDMETHODCALLTYPE SetSize(const ULARGE_INTEGER new_size) noexcept override {
        LARGE_INTEGER zero{};
        LARGE_INTEGER original{};
        if (SetFilePointerEx(handle_, zero, &original, FILE_CURRENT) == FALSE) {
            return HRESULT_FROM_WIN32(GetLastError());
        }
        if (new_size.QuadPart > static_cast<ULONGLONG>(std::numeric_limits<LONGLONG>::max())) {
            return STG_E_INVALIDFUNCTION;
        }
        LARGE_INTEGER requested{};
        requested.QuadPart = static_cast<LONGLONG>(new_size.QuadPart);
        if (SetFilePointerEx(handle_, requested, nullptr, FILE_BEGIN) == FALSE ||
            SetEndOfFile(handle_) == FALSE) {
            const HRESULT status = HRESULT_FROM_WIN32(GetLastError());
            static_cast<void>(SetFilePointerEx(handle_, original, nullptr, FILE_BEGIN));
            return status;
        }
        if (SetFilePointerEx(handle_, original, nullptr, FILE_BEGIN) == FALSE) {
            return HRESULT_FROM_WIN32(GetLastError());
        }
        return S_OK;
    }

    HRESULT STDMETHODCALLTYPE CopyTo(
        IStream* const destination,
        const ULARGE_INTEGER byte_count,
        ULARGE_INTEGER* const bytes_read,
        ULARGE_INTEGER* const bytes_written) noexcept override {
        if (destination == nullptr) {
            return STG_E_INVALIDPOINTER;
        }
        if (bytes_read != nullptr) {
            bytes_read->QuadPart = 0U;
        }
        if (bytes_written != nullptr) {
            bytes_written->QuadPart = 0U;
        }
        std::array<std::byte, 64U * 1024U> buffer{};
        ULONGLONG remaining = byte_count.QuadPart;
        while (remaining != 0U) {
            const ULONG requested = static_cast<ULONG>(std::min<ULONGLONG>(
                remaining,
                buffer.size()));
            ULONG read = 0U;
            const HRESULT read_status = Read(buffer.data(), requested, &read);
            if (FAILED(read_status)) {
                return read_status;
            }
            if (read == 0U) {
                return S_FALSE;
            }
            ULONG written = 0U;
            const HRESULT write_status = destination->Write(buffer.data(), read, &written);
            if (bytes_read != nullptr) {
                bytes_read->QuadPart += read;
            }
            if (bytes_written != nullptr) {
                bytes_written->QuadPart += written;
            }
            if (FAILED(write_status) || written != read) {
                return FAILED(write_status) ? write_status : STG_E_WRITEFAULT;
            }
            remaining -= read;
        }
        return S_OK;
    }

    HRESULT STDMETHODCALLTYPE Commit(const DWORD flags) noexcept override {
        if (flags != STGC_DEFAULT && flags != STGC_OVERWRITE) {
            return STG_E_INVALIDFLAG;
        }
        return FlushFileBuffers(handle_) != FALSE
                   ? S_OK
                   : HRESULT_FROM_WIN32(GetLastError());
    }

    HRESULT STDMETHODCALLTYPE Revert() noexcept override {
        return STG_E_REVERTED;
    }

    HRESULT STDMETHODCALLTYPE LockRegion(
        ULARGE_INTEGER,
        ULARGE_INTEGER,
        DWORD) noexcept override {
        return STG_E_INVALIDFUNCTION;
    }

    HRESULT STDMETHODCALLTYPE UnlockRegion(
        ULARGE_INTEGER,
        ULARGE_INTEGER,
        DWORD) noexcept override {
        return STG_E_INVALIDFUNCTION;
    }

    HRESULT STDMETHODCALLTYPE Stat(
        STATSTG* const statistics,
        const DWORD flags) noexcept override {
        if (statistics == nullptr) {
            return STG_E_INVALIDPOINTER;
        }
        if ((flags & ~STATFLAG_NONAME) != 0U) {
            return STG_E_INVALIDFLAG;
        }
        std::memset(statistics, 0, sizeof(*statistics));
        LARGE_INTEGER size{};
        if (GetFileSizeEx(handle_, &size) == FALSE) {
            return HRESULT_FROM_WIN32(GetLastError());
        }
        statistics->type = STGTY_STREAM;
        statistics->cbSize.QuadPart = static_cast<ULONGLONG>(size.QuadPart);
        statistics->grfMode = STGM_READWRITE | STGM_SHARE_EXCLUSIVE;
        return S_OK;
    }

    HRESULT STDMETHODCALLTYPE Clone(IStream**) noexcept override {
        return E_NOTIMPL;
    }

private:
    ~HandleStream() {
        if (handle_ != INVALID_HANDLE_VALUE) {
            static_cast<void>(CloseHandle(handle_));
        }
    }

    std::atomic<ULONG> reference_count_{1U};
    HANDLE handle_{INVALID_HANDLE_VALUE};
};

[[nodiscard]] bool destination_absent(
    const std::filesystem::path& path,
    AtomicOutputStatus& status,
    std::uint32_t& native_error_code) noexcept {
    SetLastError(ERROR_SUCCESS);
    const DWORD attributes = GetFileAttributesW(path.c_str());
    if (attributes != INVALID_FILE_ATTRIBUTES) {
        status = AtomicOutputStatus::destination_exists;
        native_error_code = ERROR_FILE_EXISTS;
        return false;
    }
    const DWORD error = GetLastError();
    if (error != ERROR_FILE_NOT_FOUND && error != ERROR_PATH_NOT_FOUND) {
        status = AtomicOutputStatus::destination_query_failed;
        native_error_code = error;
        return false;
    }
    return true;
}

[[nodiscard]] std::filesystem::path make_staging_path(
    const std::filesystem::path& parent,
    const GUID& identifier) {
    std::array<wchar_t, 40> text{};
    if (StringFromGUID2(identifier, text.data(), static_cast<int>(text.size())) <= 0) {
        return {};
    }
    const std::wstring_view identifier_text{text.data()};
    if (identifier_text.size() < 2U) {
        return {};
    }
    std::wstring name = L".negaflow-export-";
    name.append(identifier_text.substr(1U, identifier_text.size() - 2U));
    name += L".tmp";
    return parent / name;
}

[[nodiscard]] std::uint64_t file_size_from_info(
    const BY_HANDLE_FILE_INFORMATION& info) noexcept {
    return (static_cast<std::uint64_t>(info.nFileSizeHigh) << 32U) |
           static_cast<std::uint64_t>(info.nFileSizeLow);
}

}  // namespace

AtomicOutputFile::AtomicOutputFile(
    std::filesystem::path final_path,
    std::filesystem::path staging_path,
    Microsoft::WRL::ComPtr<IStream> stream) noexcept
    : final_path_(std::move(final_path)),
      staging_path_(std::move(staging_path)),
      stream_(std::move(stream)) {}

AtomicOutputFile::~AtomicOutputFile() noexcept {
    std::uint32_t ignored = 0U;
    discard(ignored);
}

AtomicOutputStatus AtomicOutputFile::create(
    const std::filesystem::path& final_path,
    std::unique_ptr<AtomicOutputFile>& output,
    std::uint32_t& native_error_code) {
    output.reset();
    native_error_code = 0U;
    if (final_path.empty() || !final_path.is_absolute() || !final_path.has_filename()) {
        return AtomicOutputStatus::invalid_path;
    }
    AtomicOutputStatus absence_status = AtomicOutputStatus::ok;
    if (!destination_absent(final_path, absence_status, native_error_code)) {
        return absence_status;
    }

    const std::filesystem::path parent = final_path.parent_path();
    const DWORD parent_attributes = GetFileAttributesW(parent.c_str());
    if (parent_attributes == INVALID_FILE_ATTRIBUTES ||
        (parent_attributes & FILE_ATTRIBUTE_DIRECTORY) == 0U) {
        native_error_code = parent_attributes == INVALID_FILE_ATTRIBUTES
                                ? static_cast<std::uint32_t>(GetLastError())
                                : ERROR_DIRECTORY;
        return AtomicOutputStatus::parent_unavailable;
    }

    for (std::uint32_t attempt = 0U; attempt < 8U; ++attempt) {
        GUID identifier{};
        const HRESULT guid_status = CoCreateGuid(&identifier);
        if (FAILED(guid_status)) {
            native_error_code = static_cast<std::uint32_t>(guid_status);
            return AtomicOutputStatus::staging_create_failed;
        }
        const std::filesystem::path staging_path = make_staging_path(parent, identifier);
        if (staging_path.empty()) {
            return AtomicOutputStatus::staging_create_failed;
        }
        const HANDLE handle = CreateFileW(
            staging_path.c_str(),
            GENERIC_READ | GENERIC_WRITE,
            0U,
            nullptr,
            CREATE_NEW,
            FILE_ATTRIBUTE_TEMPORARY | FILE_FLAG_SEQUENTIAL_SCAN,
            nullptr);
        if (handle == INVALID_HANDLE_VALUE) {
            const DWORD error = GetLastError();
            if (error == ERROR_FILE_EXISTS || error == ERROR_ALREADY_EXISTS) {
                continue;
            }
            native_error_code = error;
            return AtomicOutputStatus::staging_create_failed;
        }

        HandleStream* const raw_stream = new (std::nothrow) HandleStream(handle);
        if (raw_stream == nullptr) {
            static_cast<void>(CloseHandle(handle));
            static_cast<void>(DeleteFileW(staging_path.c_str()));
            return AtomicOutputStatus::allocation_failed;
        }
        Microsoft::WRL::ComPtr<IStream> stream{};
        stream.Attach(raw_stream);
        auto candidate = std::unique_ptr<AtomicOutputFile>(new (std::nothrow) AtomicOutputFile(
            final_path,
            staging_path,
            std::move(stream)));
        if (candidate == nullptr) {
            stream.Reset();
            static_cast<void>(DeleteFileW(staging_path.c_str()));
            return AtomicOutputStatus::allocation_failed;
        }
        output = std::move(candidate);
        return AtomicOutputStatus::ok;
    }
    native_error_code = ERROR_ALREADY_EXISTS;
    return AtomicOutputStatus::staging_create_failed;
}

IStream* AtomicOutputFile::stream() const noexcept {
    return stream_.Get();
}

const std::filesystem::path& AtomicOutputFile::staging_path() const noexcept {
    return staging_path_;
}

AtomicOutputStatus AtomicOutputFile::close_and_flush(
    std::uint32_t& native_error_code) noexcept {
    native_error_code = 0U;
    if (stream_ == nullptr) {
        return AtomicOutputStatus::ok;
    }
    const HRESULT status = stream_->Commit(STGC_DEFAULT);
    stream_.Reset();
    if (FAILED(status)) {
        native_error_code = static_cast<std::uint32_t>(status);
        return AtomicOutputStatus::flush_failed;
    }
    return AtomicOutputStatus::ok;
}

AtomicOutputStatus AtomicOutputFile::publish(
    const std::uint64_t expected_file_bytes,
    std::uint32_t& native_error_code) noexcept {
    native_error_code = 0U;
    if (stream_ != nullptr || staging_path_.empty() || published_) {
        return AtomicOutputStatus::publish_failed;
    }
    if (MoveFileExW(
            staging_path_.c_str(),
            final_path_.c_str(),
            MOVEFILE_WRITE_THROUGH) == FALSE) {
        const DWORD error = GetLastError();
        native_error_code = error;
        if (error == ERROR_FILE_EXISTS || error == ERROR_ALREADY_EXISTS) {
            return AtomicOutputStatus::destination_exists;
        }
        return AtomicOutputStatus::publish_failed;
    }
    published_ = true;

    const HANDLE final_handle = CreateFileW(
        final_path_.c_str(),
        GENERIC_READ,
        FILE_SHARE_READ,
        nullptr,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL | FILE_FLAG_SEQUENTIAL_SCAN,
        nullptr);
    if (final_handle == INVALID_HANDLE_VALUE) {
        native_error_code = static_cast<std::uint32_t>(GetLastError());
        return AtomicOutputStatus::published_file_invalid;
    }
    BY_HANDLE_FILE_INFORMATION info{};
    const BOOL info_status = GetFileInformationByHandle(final_handle, &info);
    const DWORD info_error = info_status == FALSE ? GetLastError() : ERROR_SUCCESS;
    const DWORD file_type = GetFileType(final_handle);
    static_cast<void>(CloseHandle(final_handle));
    if (info_status == FALSE || file_type != FILE_TYPE_DISK ||
        (info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0U ||
        file_size_from_info(info) != expected_file_bytes || expected_file_bytes == 0U) {
        native_error_code = static_cast<std::uint32_t>(info_error);
        return AtomicOutputStatus::published_file_invalid;
    }
    staging_path_.clear();
    return AtomicOutputStatus::ok;
}

void AtomicOutputFile::discard(std::uint32_t& native_error_code) noexcept {
    native_error_code = 0U;
    stream_.Reset();
    if (!published_ && !staging_path_.empty()) {
        if (DeleteFileW(staging_path_.c_str()) == FALSE) {
            const DWORD error = GetLastError();
            if (error != ERROR_FILE_NOT_FOUND) {
                native_error_code = error;
            }
        }
    }
    staging_path_.clear();
}

}  // namespace negaflow::output::detail
