# HLSL 컴퓨트 셰이더를 **빌드 시** 컴파일해 헤더로 임베드합니다.
# 런타임 `d3dcompiler` 의존을 두지 않기 위해서입니다 — 배포본에 컴파일러를 끌고 다니지 않고,
# 셰이더 오류를 실행 시점이 아니라 빌드에서 잡습니다.
#
# Direct3D 11 은 셰이더 모델 5.0 이고 그 컴파일러가 `fxc` 입니다.
# (SM 6.0 / `dxc` 는 D3D12 경로입니다 — 섞지 마십시오.)

find_program(
    NEGAFLOW_FXC
    NAMES fxc
    HINTS
        "$ENV{WindowsSdkVerBinPath}x64"
        "$ENV{WindowsSdkDir}bin/$ENV{WindowsSDKVersion}x64"
    PATHS
        "C:/Program Files (x86)/Windows Kits/10/bin"
    PATH_SUFFIXES
        x64
    DOC "Direct3D 11 shader compiler (Windows SDK)"
)

if(NOT NEGAFLOW_FXC)
    # 재귀로 한 번 더 찾습니다. SDK 버전 폴더가 여러 개일 수 있습니다.
    file(GLOB NEGAFLOW_FXC_CANDIDATES "C:/Program Files (x86)/Windows Kits/10/bin/*/x64/fxc.exe")
    if(NEGAFLOW_FXC_CANDIDATES)
        list(SORT NEGAFLOW_FXC_CANDIDATES)
        list(GET NEGAFLOW_FXC_CANDIDATES -1 NEGAFLOW_FXC)
    endif()
endif()

if(NOT NEGAFLOW_FXC)
    message(FATAL_ERROR "fxc.exe (Windows SDK) not found — HLSL compute shaders cannot be built")
endif()

message(STATUS "Negaflow HLSL compiler: ${NEGAFLOW_FXC}")

# negaflow_compile_compute_shader(<source.hlsl> <entry point> <symbol> <output variable>)
#
# 플래그를 왜 이렇게 주는지:
#   /T cs_5_0  D3D11 컴퓨트 셰이더.
#   /O3        최적화. 값을 바꾸는 최적화는 아래 /Gis 가 막습니다.
#   /Gis       IEEE 엄격. **이것을 빼지 마십시오** — 드라이버가 부동소수 연산을 재배열하면
#              CPU 결과와 값이 갈리고, 그러면 벤더마다 다르게 깨집니다.
#   /WX        경고를 오류로. 네이티브 C++ 와 같은 기준입니다.
#   /Zpc       행 우선 행렬. 지금은 행렬을 안 쓰지만 나중에 규칙이 흔들리지 않게 못박아 둡니다.
function(negaflow_compile_compute_shader source_path entry_point symbol_name output_variable)
    get_filename_component(source_absolute "${source_path}" ABSOLUTE)
    get_filename_component(source_stem "${source_path}" NAME_WE)
    get_filename_component(source_directory "${source_absolute}" DIRECTORY)

    # `.hlsli` 조각을 고쳐도 다시 컴파일되지 않던 문제입니다 — 의존이 `.hlsl` 하나뿐이라
    # 셰이더가 옛 조각으로 남아 있었습니다. 조각은 몇 개 안 되므로 전부 의존으로 겁니다.
    # 조각 하나를 고치면 셰이더가 전부 다시 도는 것은 의도한 것입니다: 조각은 수식을
    # 담고 있고, 조용히 옛 것으로 남는 것보다 다시 도는 편이 낫습니다.
    file(GLOB negaflow_shader_fragments CONFIGURE_DEPENDS "${source_directory}/*.hlsli")
    set(generated_header
        "${CMAKE_CURRENT_BINARY_DIR}/generated/negaflow/gpu/shaders/${source_stem}_${entry_point}.h")

    add_custom_command(
        OUTPUT "${generated_header}"
        COMMAND "${CMAKE_COMMAND}" -E make_directory
            "${CMAKE_CURRENT_BINARY_DIR}/generated/negaflow/gpu/shaders"
        COMMAND "${NEGAFLOW_FXC}"
            /nologo
            /T cs_5_0
            /E "${entry_point}"
            /Fh "${generated_header}"
            /Vn "${symbol_name}"
            /O3
            /Gis
            /WX
            /Zpc
            "${source_absolute}"
        DEPENDS "${source_absolute}" ${negaflow_shader_fragments}
        COMMENT "fxc cs_5_0 ${source_stem}:${entry_point}"
        VERBATIM
    )

    set(${output_variable} "${generated_header}" PARENT_SCOPE)
endfunction()
