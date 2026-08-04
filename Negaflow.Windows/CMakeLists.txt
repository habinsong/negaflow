cmake_minimum_required(VERSION 3.30)

project(
    NegaflowWindows
    VERSION 0.1.0
    DESCRIPTION "Negaflow native Windows foundation"
    LANGUAGES CXX
)

include(CTest)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
include(CompilerWarnings)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
# The public DLL boundary never transfers CRT-owned memory. Static CRT linkage keeps the
# native foundation runnable without a separately installed VC++ Redistributable.
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

find_package(Git QUIET)
set(NEGAFLOW_SOURCE_COMMIT "unknown")
set(NEGAFLOW_SOURCE_DIRTY 0)
if(Git_FOUND)
    execute_process(
        COMMAND "${GIT_EXECUTABLE}" rev-parse HEAD
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
        RESULT_VARIABLE NEGAFLOW_GIT_RESULT
        OUTPUT_VARIABLE NEGAFLOW_GIT_COMMIT
        ERROR_QUIET
        OUTPUT_STRIP_TRAILING_WHITESPACE
    )
    string(LENGTH "${NEGAFLOW_GIT_COMMIT}" NEGAFLOW_GIT_COMMIT_LENGTH)
    if(
        NEGAFLOW_GIT_RESULT EQUAL 0
        AND NEGAFLOW_GIT_COMMIT_LENGTH EQUAL 40
        AND NEGAFLOW_GIT_COMMIT MATCHES "^[0-9a-fA-F]+$"
    )
        string(TOLOWER "${NEGAFLOW_GIT_COMMIT}" NEGAFLOW_SOURCE_COMMIT)
    endif()

    execute_process(
        COMMAND "${GIT_EXECUTABLE}" status --porcelain --untracked-files=normal -- .
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
        RESULT_VARIABLE NEGAFLOW_GIT_STATUS_RESULT
        OUTPUT_VARIABLE NEGAFLOW_GIT_STATUS_OUTPUT
        ERROR_QUIET
        OUTPUT_STRIP_TRAILING_WHITESPACE
    )
    if(NEGAFLOW_GIT_STATUS_RESULT EQUAL 0 AND NOT NEGAFLOW_GIT_STATUS_OUTPUT STREQUAL "")
        set(NEGAFLOW_SOURCE_DIRTY 1)
    endif()
endif()

configure_file(
    src/Native/core/include/negaflow/core/build_config.h.in
    generated/negaflow/core/build_config.h
    @ONLY
)

add_library(negaflow_project_options INTERFACE)
target_compile_features(negaflow_project_options INTERFACE cxx_std_20)
target_compile_definitions(negaflow_project_options INTERFACE WIN32_LEAN_AND_MEAN NOMINMAX)
negaflow_enable_strict_warnings(negaflow_project_options)

add_library(negaflow_core STATIC
    src/Native/core/build_info.cpp
    src/Native/core/negative_inversion.cpp
    src/Native/core/pixel.cpp
    src/Native/core/pointwise.cpp
    src/Native/core/tiff_lzw_validator.cpp
    src/Native/core/tiff_probe.cpp
)
target_include_directories(negaflow_core
    PUBLIC
        "${CMAKE_CURRENT_SOURCE_DIR}/src/Native/core/include"
        "${CMAKE_CURRENT_BINARY_DIR}/generated"
)
target_link_libraries(negaflow_core PRIVATE negaflow_project_options)

add_library(negaflow_color STATIC
    src/Native/color/icc_profile.cpp
    src/Native/color/srgb_transfer.cpp
)
target_include_directories(negaflow_color
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src/Native/color/include"
)
target_link_libraries(negaflow_color PRIVATE negaflow_project_options)

add_library(negaflow_imageio STATIC
    src/Native/imageio/decoded_image.cpp
    src/Native/imageio/image_content_hash.cpp
    src/Native/imageio/image_file_observation.cpp
    src/Native/imageio/wic_tiff_decoder.cpp
)
target_include_directories(negaflow_imageio
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src/Native/imageio/include"
)
target_link_libraries(
    negaflow_imageio
    PUBLIC negaflow_core negaflow_color
    PRIVATE negaflow_project_options bcrypt windowscodecs shlwapi ole32
)

add_library(negaflow_imaging STATIC
    src/Native/imaging/color_grading.cpp
    src/Native/imaging/color_mixer.cpp
    src/Native/imaging/icm_icc_converter.cpp
    src/Native/imaging/linear_scanner_converter.cpp
    src/Native/imaging/manual_negative_developer.cpp
    src/Native/imaging/point_curve.cpp
    src/Native/imaging/primary_calibration.cpp
    src/Native/imaging/scanner_tiff_to_working.cpp
    src/Native/imaging/scanner_to_working.cpp
    src/Native/imaging/tone_curve_measurement.cpp
    src/Native/imaging/tone_mapping.cpp
    src/Native/imaging/working_tone_adjuster.cpp
)
target_include_directories(negaflow_imaging
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src/Native/imaging/include"
)
target_link_libraries(
    negaflow_imaging
    PUBLIC negaflow_core negaflow_color negaflow_imageio
    PRIVATE negaflow_project_options mscms
)

add_library(negaflow_output STATIC
    src/Native/output/atomic_output_file.cpp
    src/Native/output/png_structure_reader.cpp
    src/Native/output/tiff_ifd_allowlist.cpp
    src/Native/output/wic_png_export.cpp
    src/Native/output/wic_srgb16_support.cpp
    src/Native/output/wic_tiff_export.cpp
    src/Native/output/working_to_srgb16.cpp
)
target_include_directories(negaflow_output
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src/Native/output/include"
)
target_link_libraries(
    negaflow_output
    PUBLIC negaflow_imaging
    PRIVATE negaflow_project_options mscms windowscodecs shlwapi ole32
)

add_library(negaflow_native SHARED
    src/Native/abi/negaflow_abi.cpp
)
target_compile_definitions(negaflow_native PRIVATE NEGAFLOW_NATIVE_EXPORTS)
target_include_directories(negaflow_native
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src/Native/abi/include"
)
target_link_libraries(negaflow_native PRIVATE negaflow_core negaflow_project_options)
set_target_properties(negaflow_native PROPERTIES OUTPUT_NAME "Negaflow.Native")

add_executable(negaflow_cli
    src/Cli/main.cpp
    src/Cli/commands/develop_negative_tiff.cpp
    src/Cli/commands/export_developed_image.cpp
    src/Cli/commands/export_developed_png.cpp
    src/Cli/commands/export_developed_tiff.cpp
    src/Cli/commands/hash_image.cpp
    src/Cli/commands/prepare_scanner_tiff.cpp
    src/Cli/commands/process_cpu_time.cpp
    src/Cli/commands/working_image_report.cpp
)
target_link_libraries(
    negaflow_cli
    PRIVATE
        negaflow_core
        negaflow_color
        negaflow_imageio
        negaflow_imaging
        negaflow_output
        negaflow_project_options
)
set_target_properties(negaflow_cli PROPERTIES OUTPUT_NAME "negaflow-cli")

if(BUILD_TESTING)
    add_executable(negaflow_native_tests
        tests/Native.UnitTests/build_info_tests.cpp
    )
    target_link_libraries(
        negaflow_native_tests
        PRIVATE negaflow_core negaflow_native negaflow_project_options
    )

    add_test(NAME native.build_info COMMAND negaflow_native_tests)

    add_executable(negaflow_scalar_tests
        tests/Native.UnitTests/scalar_kernel_tests.cpp
    )
    target_include_directories(
        negaflow_scalar_tests
        PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/tests/fixtures/v1"
    )
    target_link_libraries(
        negaflow_scalar_tests
        PRIVATE negaflow_core negaflow_project_options
    )
    add_test(NAME native.scalar_kernels COMMAND negaflow_scalar_tests)

    add_executable(negaflow_tiff_probe_tests
        tests/Native.UnitTests/tiff_probe_tests.cpp
    )
    target_link_libraries(
        negaflow_tiff_probe_tests
        PRIVATE negaflow_core negaflow_project_options
    )
    add_test(NAME native.tiff_probe COMMAND negaflow_tiff_probe_tests)

    add_executable(negaflow_image_content_hash_tests
        tests/Native.UnitTests/image_content_hash_tests.cpp
    )
    target_link_libraries(
        negaflow_image_content_hash_tests
        PRIVATE negaflow_imageio negaflow_project_options
    )
    add_test(NAME native.image_content_hash COMMAND negaflow_image_content_hash_tests)

    add_executable(negaflow_image_file_observation_tests
        tests/Native.UnitTests/image_file_observation_tests.cpp
    )
    target_link_libraries(
        negaflow_image_file_observation_tests
        PRIVATE negaflow_imageio negaflow_project_options
    )
    add_test(
        NAME native.image_file_observation
        COMMAND negaflow_image_file_observation_tests
    )

    add_executable(negaflow_icc_profile_tests
        tests/Native.UnitTests/icc_profile_tests.cpp
    )
    target_link_libraries(
        negaflow_icc_profile_tests
        PRIVATE negaflow_color negaflow_project_options
    )
    add_test(NAME native.icc_profile COMMAND negaflow_icc_profile_tests)

    add_executable(negaflow_srgb_transfer_tests
        tests/Native.UnitTests/srgb_transfer_tests.cpp
    )
    target_link_libraries(
        negaflow_srgb_transfer_tests
        PRIVATE negaflow_color negaflow_project_options
    )
    add_test(NAME native.srgb_transfer COMMAND negaflow_srgb_transfer_tests)

    add_executable(negaflow_working_to_srgb16_tests
        tests/Native.UnitTests/working_to_srgb16_tests.cpp
    )
    target_link_libraries(
        negaflow_working_to_srgb16_tests
        PRIVATE negaflow_output negaflow_project_options
    )
    add_test(NAME native.working_to_srgb16 COMMAND negaflow_working_to_srgb16_tests)

    add_executable(negaflow_wic_png_export_tests
        tests/Native.UnitTests/wic_png_export_tests.cpp
    )
    target_link_libraries(
        negaflow_wic_png_export_tests
        PRIVATE negaflow_output negaflow_project_options
    )
    target_include_directories(
        negaflow_wic_png_export_tests
        PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src/Native/output"
    )
    add_test(NAME native.wic_png_export COMMAND negaflow_wic_png_export_tests)

    add_executable(negaflow_wic_tiff_export_tests
        tests/Native.UnitTests/wic_tiff_export_tests.cpp
    )
    target_link_libraries(
        negaflow_wic_tiff_export_tests
        PRIVATE negaflow_output negaflow_project_options
    )
    target_include_directories(
        negaflow_wic_tiff_export_tests
        PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src/Native/output"
    )
    add_test(NAME native.wic_tiff_export COMMAND negaflow_wic_tiff_export_tests)

    add_executable(negaflow_manual_negative_developer_tests
        tests/Native.UnitTests/manual_negative_developer_tests.cpp
    )
    target_link_libraries(
        negaflow_manual_negative_developer_tests
        PRIVATE negaflow_imaging negaflow_project_options
    )
    add_test(NAME native.manual_negative_developer COMMAND negaflow_manual_negative_developer_tests)

    add_executable(negaflow_tone_pipeline_tests
        tests/Native.UnitTests/tone_pipeline_tests.cpp
    )
    target_include_directories(
        negaflow_tone_pipeline_tests
        PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/tests/fixtures/v1"
    )
    target_link_libraries(
        negaflow_tone_pipeline_tests
        PRIVATE negaflow_imaging negaflow_project_options
    )
    add_test(NAME native.tone_pipeline COMMAND negaflow_tone_pipeline_tests)

    add_executable(negaflow_point_curve_tests
        tests/Native.UnitTests/point_curve_tests.cpp
    )
    target_include_directories(
        negaflow_point_curve_tests
        PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/tests/fixtures/v1"
    )
    target_link_libraries(
        negaflow_point_curve_tests
        PRIVATE negaflow_imaging negaflow_project_options
    )
    add_test(NAME native.point_curve COMMAND negaflow_point_curve_tests)

    add_executable(negaflow_color_mixer_tests
        tests/Native.UnitTests/color_mixer_tests.cpp
    )
    target_include_directories(
        negaflow_color_mixer_tests
        PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/tests/fixtures/v1"
    )
    target_link_libraries(
        negaflow_color_mixer_tests
        PRIVATE negaflow_imaging negaflow_project_options
    )
    add_test(NAME native.color_mixer COMMAND negaflow_color_mixer_tests)

    add_executable(negaflow_color_grading_tests
        tests/Native.UnitTests/color_grading_tests.cpp
    )
    target_include_directories(
        negaflow_color_grading_tests
        PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/tests/fixtures/v1"
    )
    target_link_libraries(
        negaflow_color_grading_tests
        PRIVATE negaflow_imaging negaflow_project_options
    )
    add_test(NAME native.color_grading COMMAND negaflow_color_grading_tests)

    add_executable(negaflow_primary_calibration_tests
        tests/Native.UnitTests/primary_calibration_tests.cpp
    )
    target_include_directories(
        negaflow_primary_calibration_tests
        PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/tests/fixtures/v1"
    )
    target_link_libraries(
        negaflow_primary_calibration_tests
        PRIVATE negaflow_imaging negaflow_project_options
    )
    add_test(
        NAME native.primary_calibration
        COMMAND negaflow_primary_calibration_tests
    )

    add_executable(negaflow_process_cpu_time_tests
        tests/Native.UnitTests/process_cpu_time_tests.cpp
        src/Cli/commands/process_cpu_time.cpp
    )
    target_include_directories(
        negaflow_process_cpu_time_tests
        PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src/Cli/commands"
    )
    target_link_libraries(
        negaflow_process_cpu_time_tests
        PRIVATE negaflow_project_options
    )
    add_test(NAME native.process_cpu_time COMMAND negaflow_process_cpu_time_tests)

    add_executable(negaflow_working_image_report_tests
        tests/Native.UnitTests/working_image_report_tests.cpp
        src/Cli/commands/working_image_report.cpp
    )
    target_include_directories(
        negaflow_working_image_report_tests
        PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src/Cli/commands"
    )
    target_link_libraries(
        negaflow_working_image_report_tests
        PRIVATE negaflow_imaging negaflow_project_options
    )
    add_test(NAME native.working_image_report COMMAND negaflow_working_image_report_tests)

    add_executable(negaflow_scanner_to_working_tests
        tests/Native.UnitTests/scanner_to_working_tests.cpp
        tests/fixtures/tiff/synthetic_wic_tiff.cpp
    )
    target_include_directories(
        negaflow_scanner_to_working_tests
        PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/tests/fixtures/tiff"
    )
    target_link_libraries(
        negaflow_scanner_to_working_tests
        PRIVATE negaflow_imaging negaflow_project_options
    )
    set(
        NEGAFLOW_SOURCE_TIFF_FIXTURE
        "${CMAKE_CURRENT_SOURCE_DIR}/../Sources/ScannerKit/Resources/Frame.tiff"
    )
    if(EXISTS "${NEGAFLOW_SOURCE_TIFF_FIXTURE}")
        add_test(
            NAME native.scanner_to_working
            COMMAND negaflow_scanner_to_working_tests "${NEGAFLOW_SOURCE_TIFF_FIXTURE}"
        )
    else()
        add_test(NAME native.scanner_to_working COMMAND negaflow_scanner_to_working_tests)
    endif()

    add_executable(negaflow_scanner_stream_parity
        tests/Native.IntegrationTests/scanner_stream_parity.cpp
    )
    target_link_libraries(
        negaflow_scanner_stream_parity
        PRIVATE negaflow_imaging negaflow_project_options
    )
    if(EXISTS "${NEGAFLOW_SOURCE_TIFF_FIXTURE}")
        add_test(
            NAME native.scanner_stream_parity
            COMMAND negaflow_scanner_stream_parity "${NEGAFLOW_SOURCE_TIFF_FIXTURE}"
        )
        set_tests_properties(
            native.scanner_stream_parity
            PROPERTIES PASS_REGULAR_EXPRESSION "\"exact_pixels_equal\":true"
        )
    endif()

    add_executable(negaflow_conformance
        tests/Native.ConformanceTests/scalar_conformance.cpp
    )
    target_include_directories(
        negaflow_conformance
        PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/tests/fixtures/v1"
    )
    target_link_libraries(
        negaflow_conformance
        PRIVATE negaflow_imaging negaflow_project_options
    )
    set_target_properties(negaflow_conformance PROPERTIES OUTPUT_NAME "negaflow-conformance")
    add_test(NAME native.scalar_conformance COMMAND negaflow_conformance)
    set_tests_properties(
        native.scalar_conformance
        PROPERTIES PASS_REGULAR_EXPRESSION "\"status\":\"ok\""
    )

    add_test(NAME cli.build_info COMMAND negaflow_cli --build-info)
    set_tests_properties(
        cli.build_info
        PROPERTIES PASS_REGULAR_EXPRESSION "\"status\":\"ok\""
    )
    add_test(
        NAME cli.negative_invert
        COMMAND negaflow_cli --negative-invert 0.72 0.72 1.55 color
    )
    set_tests_properties(
        cli.negative_invert
        PROPERTIES PASS_REGULAR_EXPRESSION "\"algorithm_version\":\"shoulder-print-response-v4\""
    )

    add_executable(negaflow_wic_tiff_decoder_tests
        tests/Native.UnitTests/wic_tiff_decoder_tests.cpp
        tests/fixtures/tiff/synthetic_wic_tiff.cpp
    )
    target_include_directories(
        negaflow_wic_tiff_decoder_tests
        PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/tests/fixtures/tiff"
    )
    target_link_libraries(
        negaflow_wic_tiff_decoder_tests
        PRIVATE negaflow_imageio negaflow_project_options
    )
    if(EXISTS "${NEGAFLOW_SOURCE_TIFF_FIXTURE}")
        add_test(
            NAME native.wic_tiff_decode
            COMMAND negaflow_wic_tiff_decoder_tests "${NEGAFLOW_SOURCE_TIFF_FIXTURE}"
        )
        add_test(
            NAME cli.probe_tiff
            COMMAND negaflow_cli --probe-tiff "${NEGAFLOW_SOURCE_TIFF_FIXTURE}"
        )
        set_tests_properties(
            cli.probe_tiff
            PROPERTIES PASS_REGULAR_EXPRESSION "\"operation\":\"probe_tiff\""
        )
        add_test(
            NAME cli.decode_tiff_wic
            COMMAND negaflow_cli --decode-tiff-wic "${NEGAFLOW_SOURCE_TIFF_FIXTURE}"
        )
        set_tests_properties(
            cli.decode_tiff_wic
            PROPERTIES PASS_REGULAR_EXPRESSION "\"operation\":\"decode_tiff_wic\""
        )
        add_test(
            NAME cli.prepare_scanner_tiff
            COMMAND negaflow_cli --prepare-scanner-tiff "${NEGAFLOW_SOURCE_TIFF_FIXTURE}"
        )
        set_tests_properties(
            cli.prepare_scanner_tiff
            PROPERTIES PASS_REGULAR_EXPRESSION "\"operation\":\"prepare_scanner_tiff\""
        )
        add_test(
            NAME cli.sha256_image
            COMMAND negaflow_cli --sha256-image "${NEGAFLOW_SOURCE_TIFF_FIXTURE}"
        )
        set_tests_properties(
            cli.sha256_image
            PROPERTIES PASS_REGULAR_EXPRESSION "\"operation\":\"sha256_image\""
        )
        add_test(
            NAME cli.develop_negative_tiff
            COMMAND negaflow_cli --develop-negative-tiff
                "${NEGAFLOW_SOURCE_TIFF_FIXTURE}" 0.72 0.32 0.15 color
        )
        set_tests_properties(
            cli.develop_negative_tiff
            PROPERTIES PASS_REGULAR_EXPRESSION
                "\"algorithm_version\":\"shoulder-print-response-v4\".*\"statistics_full_frame_scan_count\":2"
        )
        add_test(
            NAME cli.develop_negative_tiff_tone
            COMMAND negaflow_cli --develop-negative-tiff
                "${NEGAFLOW_SOURCE_TIFF_FIXTURE}" 0.72 0.32 0.15 color
                0.75 0.35 0.30 -0.25 0.20 0.40
        )
        set_tests_properties(
            cli.develop_negative_tiff_tone
            PROPERTIES PASS_REGULAR_EXPRESSION
                "\"pixel_fingerprint_algorithm\":\"fnv1a64-rgba32f-bits-le-v1\".*\"statistics_full_frame_scan_count\":3"
        )
    else()
        add_test(NAME native.wic_tiff_decode COMMAND negaflow_wic_tiff_decoder_tests)
    endif()
endif()
