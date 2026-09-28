#pragma once

#include <d3d11.h>

#include <cstdint>

namespace negaflow::gpu {

class GpuDevice;

namespace staging_detail {

// 작업 형식(RGBA32F) 스테이징 한 장을 새로 만듭니다. `cpu_access` 는 읽기 또는 쓰기 하나입니다.
[[nodiscard]] ID3D11Texture2D* make_staging(
    const GpuDevice& device,
    std::uint32_t width,
    std::uint32_t height,
    UINT cpu_access) noexcept;

// 장치·방향(올리기/내리기)마다 크기 두 벌(인터랙티브·정착)의 스테이징을 **나눠 씁니다.**
//
// 예전에는 텍스처마다 올리기·내리기 스테이징을 따로 들어, 현상 타깃이 걸린 7.8MP 한 장에서
// 스테이징만 6장(756 MB, 언제나 시스템 RAM)이었습니다. 장치 작업은 가속기 잠금 아래 한
// 컨텍스트에서 차례로 돌므로 같은 크기의 스테이징 하나로 충분합니다. 읽기와 쓰기를 한 장에
// 겸하지 않는 이유는 `gpu_working_image.h` 에 있습니다(READ|WRITE 는 읽기 캐시 정책을 낮춥니다).
//
// 돌려준 포인터는 같은 장치로 다른 크기를 두 번 더 청하기 전까지 유효합니다.
[[nodiscard]] ID3D11Texture2D* shared_staging(
    const GpuDevice& device,
    std::uint32_t width,
    std::uint32_t height,
    UINT cpu_access) noexcept;

}  // namespace staging_detail

}  // namespace negaflow::gpu
