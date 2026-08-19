// 네이티브에서 죽을 때 어디서 죽었는지 남깁니다.
//
// 2026-08-20 사용자 보고: 자동 레벨 단추를 여러 번 누르면 앱이 강제 종료됩니다.
// 이벤트 로그에는 `Negaflow.Native.dll` 안의 액세스 위반과 **오프셋 하나**만 남아,
// 어느 함수인지 알 수 없었습니다. 그래서 죽는 순간에 예외 코드·주소·모듈 기준 RVA 와
// 되돌아갈 주소들의 RVA 를 파일로 남깁니다. `scripts/symbolize-rva.ps1` 이 그 RVA 를
// 함수·줄로 되돌립니다(Release 도 PDB 를 냅니다).
//
// 로그: %LOCALAPPDATA%\Negaflow\Logs\native-crash.txt (없으면 %TEMP%)

#include <windows.h>

#include <cstdint>
#include <cstdio>
#include <cstring>

namespace {

HMODULE this_module() noexcept {
    HMODULE module = nullptr;
    ::GetModuleHandleExW(
        GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
        reinterpret_cast<LPCWSTR>(&this_module),
        &module);
    return module;
}

void log_path(wchar_t* const buffer, const std::size_t capacity) noexcept {
    wchar_t local[MAX_PATH]{};
    DWORD length = ::GetEnvironmentVariableW(L"LOCALAPPDATA", local, MAX_PATH);
    if (length == 0U || length >= MAX_PATH) {
        length = ::GetEnvironmentVariableW(L"TEMP", local, MAX_PATH);
    }
    if (length == 0U || length >= MAX_PATH) {
        ::wcsncpy_s(buffer, capacity, L"negaflow-native-crash.txt", _TRUNCATE);
        return;
    }
    ::swprintf_s(buffer, capacity, L"%s\\Negaflow\\Logs", local);
    ::CreateDirectoryW(buffer, nullptr);
    ::swprintf_s(buffer, capacity, L"%s\\Negaflow\\Logs\\native-crash.txt", local);
}

LONG CALLBACK write_crash(EXCEPTION_POINTERS* const pointers) noexcept {
    if (pointers == nullptr || pointers->ExceptionRecord == nullptr) {
        return EXCEPTION_CONTINUE_SEARCH;
    }
    const DWORD code = pointers->ExceptionRecord->ExceptionCode;
    // 계속 진행할 수 있는 예외(C++ throw, 브레이크포인트 등)는 남기지 않습니다.
    if (code != EXCEPTION_ACCESS_VIOLATION && code != EXCEPTION_STACK_OVERFLOW &&
        code != EXCEPTION_ILLEGAL_INSTRUCTION && code != EXCEPTION_INT_DIVIDE_BY_ZERO &&
        code != EXCEPTION_PRIV_INSTRUCTION) {
        return EXCEPTION_CONTINUE_SEARCH;
    }

    wchar_t path[MAX_PATH]{};
    log_path(path, MAX_PATH);
    FILE* file = nullptr;
    if (::_wfopen_s(&file, path, L"a") != 0 || file == nullptr) {
        return EXCEPTION_CONTINUE_SEARCH;
    }

    SYSTEMTIME now{};
    ::GetLocalTime(&now);
    const auto base = reinterpret_cast<std::uintptr_t>(this_module());
    const auto address =
        reinterpret_cast<std::uintptr_t>(pointers->ExceptionRecord->ExceptionAddress);
    std::fprintf(
        file,
        "%04u-%02u-%02u %02u:%02u:%02u code=0x%08lx address=0x%llx base=0x%llx rva=0x%llx thread=%lu\n",
        now.wYear, now.wMonth, now.wDay, now.wHour, now.wMinute, now.wSecond,
        static_cast<unsigned long>(code),
        static_cast<unsigned long long>(address),
        static_cast<unsigned long long>(base),
        static_cast<unsigned long long>(address >= base ? address - base : 0U),
        ::GetCurrentThreadId());
    if (code == EXCEPTION_ACCESS_VIOLATION &&
        pointers->ExceptionRecord->NumberParameters >= 2U) {
        std::fprintf(
            file,
            "  access %s at 0x%llx\n",
            pointers->ExceptionRecord->ExceptionInformation[0] == 0U ? "read" : "write",
            static_cast<unsigned long long>(
                pointers->ExceptionRecord->ExceptionInformation[1]));
    }

    void* frames[32]{};
    const USHORT captured = ::RtlCaptureStackBackTrace(0U, 32U, frames, nullptr);
    for (USHORT index = 0U; index < captured; ++index) {
        const auto frame = reinterpret_cast<std::uintptr_t>(frames[index]);
        HMODULE owner = nullptr;
        ::GetModuleHandleExW(
            GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
            reinterpret_cast<LPCWSTR>(frames[index]),
            &owner);
        wchar_t name[MAX_PATH]{};
        if (owner != nullptr) {
            ::GetModuleFileNameW(owner, name, MAX_PATH);
        }
        const wchar_t* leaf = ::wcsrchr(name, L'\\');
        const auto owner_base = reinterpret_cast<std::uintptr_t>(owner);
        std::fprintf(
            file,
            "  #%02u %ls+0x%llx\n",
            static_cast<unsigned>(index),
            leaf != nullptr ? leaf + 1 : L"?",
            static_cast<unsigned long long>(frame >= owner_base ? frame - owner_base : 0U));
    }
    std::fprintf(file, "\n");
    std::fclose(file);
    return EXCEPTION_CONTINUE_SEARCH;
}

struct CrashLogInstaller final {
    CrashLogInstaller() noexcept {
        // 첫 번째 처리기로 넣습니다. 죽는 순간의 스택이 필요하고, 계속 검색하게
        // 두므로 기존 동작(WER 보고)은 그대로입니다.
        handle_ = ::AddVectoredExceptionHandler(1UL, &write_crash);
    }

    ~CrashLogInstaller() {
        if (handle_ != nullptr) {
            ::RemoveVectoredExceptionHandler(handle_);
        }
    }

    CrashLogInstaller(const CrashLogInstaller&) = delete;
    CrashLogInstaller& operator=(const CrashLogInstaller&) = delete;
    CrashLogInstaller(CrashLogInstaller&&) = delete;
    CrashLogInstaller& operator=(CrashLogInstaller&&) = delete;

private:
    PVOID handle_{nullptr};
};

const CrashLogInstaller installer{};

}  // namespace
