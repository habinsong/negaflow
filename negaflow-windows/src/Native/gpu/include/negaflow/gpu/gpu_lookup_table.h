#pragma once

// 셰이더가 읽는 **표**입니다. 3D LUT · 측정 이식 표처럼 화소마다 같은 값을 담습니다.
//
// 왜 `Texture3D` 가 아닌가 — 하드웨어 삼선형 필터의 가중치는 **8비트 고정소수**입니다.
// D3D11 은 서브텍셀 정밀도를 8비트만 보장하므로, 보간 계수가 1/256 로 양자화됩니다.
// 33³ 큐브의 이웃 간격이 값으로 1/32 쯤이라 그 양자화는 출력에 6e-05 대로 실립니다 —
// **`1e-5` 동치를 못 지킵니다.** 그래서 표를 구조화 버퍼로 올리고 보간은 셰이더가
// **CPU 와 같은 float 연산으로** 직접 합니다. 그러면 곱셈·덧셈이 같은 순서라 값이 같습니다.
// 출처: [Texture filtering](https://learn.microsoft.com/en-us/windows/win32/direct3d11/d3d10-graphics-programming-guide-resources-textures-filtering)
//
// 상수 버퍼가 아닌 이유 — D3D11 상수 버퍼 상한은 4096 벡터(64 KB)이고 33³×12바이트는
// 431 KB 입니다. 구조화 버퍼는 그 상한이 없습니다.

#include <cstddef>

#include "negaflow/gpu/gpu_pointwise.h"

struct ID3D11Buffer;

namespace negaflow::gpu {

class GpuDevice;

class GpuLookupTable final {
public:
    GpuLookupTable() noexcept = default;
    ~GpuLookupTable();

    GpuLookupTable(const GpuLookupTable&) = delete;
    GpuLookupTable& operator=(const GpuLookupTable&) = delete;
    GpuLookupTable(GpuLookupTable&& other) noexcept;
    GpuLookupTable& operator=(GpuLookupTable&& other) noexcept;

    // `element_bytes` 는 셰이더의 `StructuredBuffer<T>` 원소 크기와 같아야 합니다.
    // 어긋나면 컴파일·실행·경고가 전부 통과하고 **값만 틀립니다** — 박스 블러의
    // 상수 버퍼 패딩 사고와 같은 종류입니다.
    [[nodiscard]] static GpuKernelStatus create(
        const GpuDevice& device,
        std::size_t element_count,
        std::size_t element_bytes,
        GpuLookupTable& table) noexcept;

    // 내용만 바꿉니다. 크기가 다르면 거절합니다 — 조용히 다시 만들면 셰이더가 이미
    // 묶어 둔 SRV 가 옛 버퍼를 가리킵니다.
    [[nodiscard]] GpuKernelStatus upload(
        const GpuDevice& device,
        const void* data,
        std::size_t element_count) const noexcept;

    [[nodiscard]] ID3D11ShaderResourceView* srv() const noexcept { return srv_; }
    [[nodiscard]] bool is_valid() const noexcept { return srv_ != nullptr; }
    [[nodiscard]] std::size_t element_count() const noexcept { return element_count_; }

private:
    void reset() noexcept;

    ID3D11Buffer* buffer_{nullptr};
    ID3D11ShaderResourceView* srv_{nullptr};
    std::size_t element_count_{0U};
    std::size_t element_bytes_{0U};
};

}  // namespace negaflow::gpu
