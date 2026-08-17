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
    src/Native/core/parallel_rows.cpp
    src/Native/core/pixel.cpp
    src/Native/core/pointwise.cpp
    src/Native/core/tiff_deflate_validator.cpp
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
    src/Native/color/soft_proof.cpp
    src/Native/color/gamut_check.cpp
    src/Native/color/output_color_space.cpp
    src/Native/color/srgb_transfer.cpp
)
target_include_directories(negaflow_color
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src/Native/color/include"
)
target_link_libraries(negaflow_color PRIVATE negaflow_project_options)
# ICM 의 gamut-check 변환(mscms)을 씁니다. 색역 판정은 근사하지 않습니다.
target_link_libraries(negaflow_color PUBLIC mscms)

add_library(negaflow_imageio STATIC
    src/Native/imageio/decoded_image.cpp
    src/Native/imageio/image_content_hash.cpp
    src/Native/imageio/image_file_observation.cpp
    src/Native/imageio/wic_standard_image_decoder.cpp
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
    src/Native/imaging/auto_adjust.cpp
    src/Native/imaging/auto_negative_base_resolver.cpp
    src/Native/imaging/film_stock_base_resolver.cpp
    src/Native/imaging/color_grading.cpp
    src/Native/imaging/color_mixer.cpp
    src/Native/imaging/film_emulation_acutance.cpp
    src/Native/imaging/film_emulation_acutance_profiles.cpp
      src/Native/imaging/film_emulation_color.cpp
      src/Native/imaging/film_emulation_profiles.cpp
      src/Native/imaging/film_emulation_registry.cpp
      src/Native/imaging/film_scan_denoise.cpp
      src/Native/imaging/bw_toning.cpp
      src/Native/imaging/color_model.cpp
      src/Native/imaging/digital_bw_emulsion_response.cpp
      src/Native/imaging/digital_bw_film_look.cpp
      src/Native/imaging/digital_bw_film_profile.cpp
      src/Native/imaging/digital_film_color_preset.cpp
      src/Native/imaging/digital_film_grain.cpp
      src/Native/imaging/digital_film_physics.cpp
      src/Native/imaging/digital_halation.cpp
      src/Native/imaging/defect_component_repair.cpp
      src/Native/imaging/defect_component_mask.cpp
      src/Native/imaging/defect_component_structure.cpp
      src/Native/imaging/defect_component_texture.cpp
      src/Native/imaging/defect_clone_stamp.cpp
      src/Native/imaging/defect_heal_brush.cpp
      src/Native/imaging/grain_mend.cpp
      src/Native/imaging/grain_mend_classifier.cpp
      src/Native/imaging/grain_mend_component_classification.cpp
      src/Native/imaging/grain_mend_component_gates.cpp
      src/Native/imaging/grain_mend_components.cpp
      src/Native/imaging/grain_mend_detection_image.cpp
      src/Native/imaging/grain_mend_detector.cpp
      src/Native/imaging/grain_mend_scratch_angles.cpp
      src/Native/imaging/grain_mend_grain_field.cpp
      src/Native/imaging/grain_mend_mask_paint.cpp
      src/Native/imaging/grain_mend_shape.cpp
      src/Native/imaging/grain_mend_structure_lines.cpp
      src/Native/imaging/grain_mend_morphology.cpp
      src/Native/imaging/grain_mend_resample.cpp
      src/Native/imaging/grain_mend_speck_detector.cpp
      src/Native/imaging/grain_mend_tiled.cpp
      src/Native/imaging/flatbed_frame_grid_detector.cpp
      src/Native/imaging/infrared_defect_detector.cpp
      src/Native/imaging/icm_icc_converter.cpp
      src/Native/imaging/image_transform.cpp
      src/Native/imaging/working_image_resample.cpp
    src/Native/imaging/linear_scanner_converter.cpp
      src/Native/imaging/local_dodge_burn.cpp
      src/Native/imaging/muted_scene_vibrance.cpp
      src/Native/imaging/muted_scene_vibrance_table.cpp
      src/Native/imaging/scene_correction.cpp
      src/Native/imaging/rescue_grade.cpp
      src/Native/imaging/scanner_profile_grade.cpp
      src/Native/imaging/scanner_target_grade.cpp
    src/Native/imaging/manual_negative_developer.cpp
    src/Native/imaging/mipmap_downsampler.cpp
    src/Native/imaging/point_curve.cpp
    src/Native/imaging/primary_calibration.cpp
    src/Native/imaging/scanner_tiff_to_working.cpp
    src/Native/imaging/scanner_to_working.cpp
    src/Native/imaging/tone_curve_measurement.cpp
    src/Native/imaging/tone_mapping.cpp
    src/Native/imaging/texture_stage.cpp
    src/Native/imaging/working_film_look.cpp
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
    src/Native/output/export_metadata.cpp
    src/Native/output/png_structure_reader.cpp
    src/Native/output/tiff_ifd_allowlist.cpp
    src/Native/output/wic_jpeg_export.cpp
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

# The develop-and-export sequence used to live inside the CLI, which meant the C ABI
# could not run the pipeline without a second copy of it. It is a library now so the
# CLI and the shell drive exactly the same code.
add_library(negaflow_pipeline STATIC
    src/Native/pipeline/defect_infrared_stage.cpp
    src/Native/pipeline/defect_recipe_stage.cpp
    src/Native/pipeline/defect_region_stage.cpp
    src/Native/pipeline/develop_export.cpp
    src/Native/pipeline/film_look_workspace.cpp
)
target_include_directories(negaflow_pipeline
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src/Native/pipeline/include"
)
target_link_libraries(
    negaflow_pipeline
    PUBLIC
        negaflow_color
        negaflow_imageio
        negaflow_imaging
        negaflow_output
    PRIVATE
        negaflow_core
        negaflow_project_options
)

add_library(negaflow_native SHARED
    src/Native/abi/negaflow_abi.cpp
)
target_compile_definitions(negaflow_native PRIVATE NEGAFLOW_NATIVE_EXPORTS)
target_include_directories(negaflow_native
    PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src/Native/abi/include"
)
target_link_libraries(
    negaflow_native
    PRIVATE
        negaflow_core
        negaflow_color
        negaflow_imageio
        negaflow_imaging
        negaflow_output
        negaflow_pipeline
        negaflow_project_options
)
set_target_properties(negaflow_native PROPERTIES OUTPUT_NAME "Negaflow.Native")

add_executable(negaflow_cli
    src/Cli/main.cpp
    src/Cli/commands/develop_negative_tiff.cpp
    src/Cli/commands/Export/developed_export_options.cpp
    src/Cli/commands/Export/developed_export_report.cpp
    src/Cli/commands/Export/export_developed_image_command.cpp
    src/Cli/commands/export_developed_png.cpp
    src/Cli/commands/export_developed_tiff.cpp
    src/Cli/commands/film_look_command_support.cpp
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
        negaflow_pipeline
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

    add_executable(negaflow_develop_export_abi_tests
        tests/Native.UnitTests/develop_export_abi_tests.cpp
        tests/fixtures/tiff/synthetic_wic_tiff.cpp
    )
    target_include_directories(
        negaflow_develop_export_abi_tests
        PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/tests/fixtures/tiff"
    )
    target_link_libraries(
        negaflow_develop_export_abi_tests
        PRIVATE negaflow_native negaflow_color negaflow_imaging negaflow_project_options
    )

    add_executable(negaflow_task9_bw_slide_golden_tests
        tests/Native.UnitTests/task9_bw_slide_golden_tests.cpp
    )
    target_link_libraries(
        negaflow_task9_bw_slide_golden_tests
        PRIVATE negaflow_native negaflow_color negaflow_imaging negaflow_project_options
    )
    add_test(
        NAME native.task9_bw_slide_golden
        COMMAND negaflow_task9_bw_slide_golden_tests
            "${CMAKE_CURRENT_SOURCE_DIR}/../docs/verification/macos-golden/task9-bw-slide"
    )

    # Task 1's source TIFF is intentionally outside the repository. The
    # executable takes its source and golden directories as explicit arguments
    # so a machine-local path is never compiled into the product or CTest.
    add_executable(negaflow_task1_pixel_golden_tests
        tests/Native.UnitTests/task1_pixel_golden_tests.cpp
    )
    target_link_libraries(
        negaflow_task1_pixel_golden_tests
        PRIVATE negaflow_native negaflow_color negaflow_imaging negaflow_imageio
            negaflow_project_options
    )

    add_executable(negaflow_task6_metadata_golden_tests
        tests/Native.UnitTests/task6_metadata_golden_tests.cpp
    )
    target_link_libraries(
        negaflow_task6_metadata_golden_tests
        PRIVATE negaflow_output negaflow_project_options
    )
    add_test(
        NAME native.task6_metadata_golden
        COMMAND negaflow_task6_metadata_golden_tests
            "${CMAKE_CURRENT_SOURCE_DIR}/../docs/verification/macos-golden/task6-metadata-policy"
    )

    add_executable(negaflow_infrared_detector_abi_tests
        tests/Native.UnitTests/infrared_detector_abi_tests.cpp
        tests/fixtures/tiff/synthetic_wic_tiff.cpp
    )
    target_include_directories(
        negaflow_infrared_detector_abi_tests
        PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/tests/fixtures/tiff"
    )
    target_link_libraries(
        negaflow_infrared_detector_abi_tests
        PRIVATE negaflow_native negaflow_project_options
    )
    add_test(
        NAME native.infrared_detector_abi
        COMMAND negaflow_infrared_detector_abi_tests
    )

    add_executable(negaflow_flatbed_frame_grid_abi_tests
        tests/Native.UnitTests/flatbed_frame_grid_abi_tests.cpp
    )
    target_link_libraries(
        negaflow_flatbed_frame_grid_abi_tests
        PRIVATE negaflow_native negaflow_project_options
    )
    add_test(
        NAME native.flatbed_frame_grid_abi
        COMMAND negaflow_flatbed_frame_grid_abi_tests
    )

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

    add_executable(negaflow_output_color_space_tests
        tests/Native.UnitTests/output_color_space_tests.cpp
    )
    target_link_libraries(
        negaflow_output_color_space_tests
        PRIVATE negaflow_color negaflow_project_options
    )
    add_test(NAME native.output_color_space COMMAND negaflow_output_color_space_tests)

    add_executable(negaflow_gamut_check_tests
        tests/Native.UnitTests/gamut_check_tests.cpp
    )
    target_link_libraries(
        negaflow_gamut_check_tests
        PRIVATE negaflow_color negaflow_project_options
    )
    add_test(NAME native.gamut_check COMMAND negaflow_gamut_check_tests)

    add_executable(negaflow_icc_profile_tests
        tests/Native.UnitTests/icc_profile_tests.cpp
    )
    target_link_libraries(
        negaflow_icc_profile_tests
        PRIVATE negaflow_color negaflow_project_options
    )
    add_test(NAME native.icc_profile COMMAND negaflow_icc_profile_tests)

    add_executable(negaflow_soft_proof_tests
        tests/Native.UnitTests/soft_proof_tests.cpp
    )
    target_link_libraries(
        negaflow_soft_proof_tests
        PRIVATE negaflow_color negaflow_project_options
    )
    add_test(NAME native.soft_proof COMMAND negaflow_soft_proof_tests)

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
        PRIVATE negaflow_output negaflow_imaging negaflow_project_options
    )
    target_include_directories(
        negaflow_wic_png_export_tests
        PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src/Native/output"
    )
    add_test(NAME native.wic_png_export COMMAND negaflow_wic_png_export_tests)

    add_executable(negaflow_wic_jpeg_export_tests
        tests/Native.UnitTests/wic_jpeg_export_tests.cpp
    )
    target_link_libraries(
        negaflow_wic_jpeg_export_tests
        PRIVATE negaflow_output negaflow_imaging negaflow_project_options
    )
    target_include_directories(
        negaflow_wic_jpeg_export_tests
        PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src/Native/output"
    )
    add_test(NAME native.wic_jpeg_export COMMAND negaflow_wic_jpeg_export_tests)

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

    add_executable(negaflow_film_emulation_color_tests
        tests/Native.UnitTests/film_emulation_color_tests.cpp
    )
    target_include_directories(
        negaflow_film_emulation_color_tests
        PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/tests/fixtures/v1"
    )
    target_link_libraries(
        negaflow_film_emulation_color_tests
        PRIVATE negaflow_imaging negaflow_project_options
    )
    add_test(
        NAME native.film_emulation_color
        COMMAND negaflow_film_emulation_color_tests
    )

    add_executable(negaflow_film_emulation_acutance_tests
        tests/Native.UnitTests/film_emulation_acutance_tests.cpp
    )
    target_include_directories(
        negaflow_film_emulation_acutance_tests
        PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/tests/fixtures/v1"
    )
    target_link_libraries(
        negaflow_film_emulation_acutance_tests
        PRIVATE negaflow_imaging negaflow_project_options
    )
    add_test(
        NAME native.film_emulation_acutance
        COMMAND negaflow_film_emulation_acutance_tests
    )

    add_executable(negaflow_working_film_look_tests
        tests/Native.UnitTests/working_film_look_tests.cpp
    )
    target_include_directories(
        negaflow_working_film_look_tests
        PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/tests/fixtures/v1"
    )
    target_link_libraries(
        negaflow_working_film_look_tests
        PRIVATE negaflow_imaging negaflow_project_options
    )
    add_test(
        NAME native.working_film_look
        COMMAND negaflow_working_film_look_tests
            "${CMAKE_CURRENT_SOURCE_DIR}/../docs/verification/macos-golden/task8-digital-film-look"
    )

    add_executable(negaflow_grain_mend_tests
        tests/Native.UnitTests/grain_mend_tests.cpp
    )
    target_include_directories(
        negaflow_grain_mend_tests
        PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src/Native/imaging"
    )
    target_link_libraries(
        negaflow_grain_mend_tests
        PRIVATE negaflow_imaging negaflow_project_options
    )
    add_test(NAME native.grain_mend COMMAND negaflow_grain_mend_tests)

    add_executable(negaflow_flatbed_frame_grid_tests
        tests/Native.UnitTests/flatbed_frame_grid_detector_tests.cpp
    )
    target_link_libraries(
        negaflow_flatbed_frame_grid_tests
        PRIVATE negaflow_imaging negaflow_project_options
    )
    add_test(
        NAME native.flatbed_frame_grid
        COMMAND negaflow_flatbed_frame_grid_tests
    )

    add_executable(negaflow_defect_component_repair_tests
        tests/Native.UnitTests/defect_component_repair_tests.cpp
    )
    target_link_libraries(
        negaflow_defect_component_repair_tests
        PRIVATE negaflow_imaging negaflow_project_options
    )
    add_test(
        NAME native.defect_component_repair
        COMMAND negaflow_defect_component_repair_tests
    )

    add_executable(negaflow_defect_infrared_stage_tests
        tests/Native.UnitTests/defect_infrared_stage_tests.cpp
    )
    target_link_libraries(
        negaflow_defect_infrared_stage_tests
        PRIVATE negaflow_pipeline negaflow_project_options
    )
    add_test(
        NAME native.defect_infrared_stage
        COMMAND negaflow_defect_infrared_stage_tests
    )

    add_executable(negaflow_infrared_defect_detector_tests
        tests/Native.UnitTests/infrared_defect_detector_tests.cpp
    )
    target_link_libraries(
        negaflow_infrared_defect_detector_tests
        PRIVATE negaflow_imaging negaflow_project_options
    )
    add_test(
        NAME native.infrared_defect_detector
        COMMAND negaflow_infrared_defect_detector_tests
    )

    add_executable(negaflow_defect_clone_stamp_tests
        tests/Native.UnitTests/defect_clone_stamp_tests.cpp
    )
    target_link_libraries(
        negaflow_defect_clone_stamp_tests
        PRIVATE negaflow_imaging negaflow_project_options
    )
    add_test(
        NAME native.defect_clone_stamp
        COMMAND negaflow_defect_clone_stamp_tests
    )

    add_executable(negaflow_defect_heal_brush_tests
        tests/Native.UnitTests/defect_heal_brush_tests.cpp
    )
    target_link_libraries(
        negaflow_defect_heal_brush_tests
        PRIVATE negaflow_imaging negaflow_project_options
    )
    add_test(
        NAME native.defect_heal_brush
        COMMAND negaflow_defect_heal_brush_tests
    )

    # The pinned FILM-R corpus is downloaded on demand and is not shipped. This
    # executable is intentionally not a default CTest because its 44 pairs are
    # about 438 MB and belong at image-quality checkpoints only.
    add_executable(negaflow_grain_mend_corpus_tests
        tests/Native.UnitTests/grain_mend_corpus_tests.cpp
    )
    target_link_libraries(
        negaflow_grain_mend_corpus_tests
        PRIVATE
            negaflow_imaging
            negaflow_project_options
            windowscodecs
            ole32
    )

    add_executable(negaflow_film_scan_denoise_tests
        tests/Native.UnitTests/film_scan_denoise_tests.cpp
    )
    target_link_libraries(
        negaflow_film_scan_denoise_tests
        PRIVATE negaflow_imaging negaflow_project_options
    )
    add_test(
        NAME native.film_scan_denoise
        COMMAND negaflow_film_scan_denoise_tests
    )

    add_executable(negaflow_local_dodge_burn_tests
        tests/Native.UnitTests/local_dodge_burn_tests.cpp
    )
    target_link_libraries(
        negaflow_local_dodge_burn_tests
        PRIVATE negaflow_imaging negaflow_project_options
    )
    add_test(
        NAME native.local_dodge_burn
        COMMAND negaflow_local_dodge_burn_tests
    )

    add_executable(negaflow_color_model_tests
        tests/Native.UnitTests/color_model_tests.cpp
    )
    target_link_libraries(
        negaflow_color_model_tests
        PRIVATE negaflow_imaging negaflow_project_options
    )
    add_test(
        NAME native.color_model
        COMMAND negaflow_color_model_tests
            "${CMAKE_CURRENT_SOURCE_DIR}/../docs/verification/macos-golden/vibrance"
    )

    add_executable(negaflow_scene_correction_tests
        tests/Native.UnitTests/scene_correction_tests.cpp
    )
    target_link_libraries(
        negaflow_scene_correction_tests
        PRIVATE negaflow_imaging negaflow_project_options
    )
    add_test(NAME native.scene_correction COMMAND negaflow_scene_correction_tests)

    add_executable(negaflow_rescue_grade_tests
        tests/Native.UnitTests/rescue_grade_tests.cpp
    )
    target_link_libraries(
        negaflow_rescue_grade_tests
        PRIVATE negaflow_imaging negaflow_project_options
    )
    add_test(NAME native.rescue_grade COMMAND negaflow_rescue_grade_tests)

    add_executable(negaflow_scanner_profile_grade_tests
        tests/Native.UnitTests/scanner_profile_grade_tests.cpp
    )
    target_link_libraries(
        negaflow_scanner_profile_grade_tests
        PRIVATE negaflow_imaging negaflow_project_options
    )
    add_test(
        NAME native.scanner_profile_grade
        COMMAND negaflow_scanner_profile_grade_tests
    )

    add_executable(negaflow_scanner_target_grade_tests
        tests/Native.UnitTests/scanner_target_grade_tests.cpp
    )
    target_link_libraries(
        negaflow_scanner_target_grade_tests
        PRIVATE negaflow_imaging negaflow_project_options
    )
    add_test(
        NAME native.scanner_target_grade
        COMMAND negaflow_scanner_target_grade_tests
    )

    add_executable(negaflow_texture_stage_tests
        tests/Native.UnitTests/texture_stage_tests.cpp
    )
    target_link_libraries(
        negaflow_texture_stage_tests
        PRIVATE negaflow_imaging negaflow_project_options
    )
    add_test(
        NAME native.texture_stage
        COMMAND negaflow_texture_stage_tests
            "${CMAKE_CURRENT_SOURCE_DIR}/../docs/verification/macos-golden/task7-coreimage-filters"
    )

    add_executable(negaflow_bw_toning_tests
        tests/Native.UnitTests/bw_toning_tests.cpp
    )
    target_link_libraries(
        negaflow_bw_toning_tests
        PRIVATE negaflow_imaging negaflow_project_options
    )
    add_test(NAME native.bw_toning COMMAND negaflow_bw_toning_tests)

    add_executable(negaflow_image_transform_tests
        tests/Native.UnitTests/image_transform_tests.cpp
    )
    target_link_libraries(
        negaflow_image_transform_tests
        PRIVATE negaflow_imaging negaflow_project_options
    )
    add_test(NAME native.image_transform COMMAND negaflow_image_transform_tests)

    add_executable(negaflow_working_image_resample_tests
        tests/Native.UnitTests/working_image_resample_tests.cpp
    )
    target_link_libraries(
        negaflow_working_image_resample_tests
        PRIVATE negaflow_imaging negaflow_project_options
    )
    add_test(
        NAME native.working_image_resample
        COMMAND negaflow_working_image_resample_tests
    )

    add_executable(negaflow_digital_film_material_tests
        tests/Native.UnitTests/digital_film_material_tests.cpp
    )
    target_link_libraries(
        negaflow_digital_film_material_tests
        PRIVATE negaflow_imaging negaflow_project_options
    )
    add_test(
        NAME native.digital_film_material
        COMMAND negaflow_digital_film_material_tests
    )

    add_executable(negaflow_digital_bw_film_look_tests
        tests/Native.UnitTests/digital_bw_film_look_tests.cpp
    )
    target_link_libraries(
        negaflow_digital_bw_film_look_tests
        PRIVATE negaflow_imaging negaflow_project_options
    )
    add_test(
        NAME native.digital_bw_film_look
        COMMAND negaflow_digital_bw_film_look_tests
    )

    add_executable(negaflow_film_look_command_support_tests
        tests/Native.UnitTests/film_look_command_support_tests.cpp
        src/Cli/commands/film_look_command_support.cpp
    )
    target_include_directories(
        negaflow_film_look_command_support_tests
        PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src/Cli/commands"
    )
    target_link_libraries(
        negaflow_film_look_command_support_tests
        PRIVATE negaflow_imaging negaflow_pipeline negaflow_project_options
    )
    add_test(
        NAME cli.film_look_command_support
        COMMAND negaflow_film_look_command_support_tests
    )

    add_executable(negaflow_auto_adjust_tests
        tests/Native.UnitTests/auto_adjust_tests.cpp
    )
    target_link_libraries(
        negaflow_auto_adjust_tests
        PRIVATE negaflow_imaging negaflow_project_options
    )
    add_test(NAME native.auto_adjust COMMAND negaflow_auto_adjust_tests)

    add_executable(negaflow_display_gamut_map_tests
        tests/Native.UnitTests/display_gamut_map_tests.cpp
    )
    target_link_libraries(
        negaflow_display_gamut_map_tests
        PRIVATE negaflow_imaging negaflow_project_options
    )
    add_test(NAME native.display_gamut_map COMMAND negaflow_display_gamut_map_tests)

    add_executable(negaflow_parallel_rows_tests
        tests/Native.UnitTests/parallel_rows_tests.cpp
    )
    target_link_libraries(
        negaflow_parallel_rows_tests
        PRIVATE negaflow_core negaflow_project_options
    )
    add_test(NAME native.parallel_rows COMMAND negaflow_parallel_rows_tests)

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
    # The reference macOS checkout owns this scan; it is read, never written. The path
    # used to be one segment short, which silently degraded every real-TIFF test to its
    # synthetic-only branch — the checks looked like they were running and were not.
    set(
        NEGAFLOW_SOURCE_TIFF_FIXTURE
        "${CMAKE_CURRENT_SOURCE_DIR}/../negaflow-mac/Sources/ScannerKit/Resources/Frame.tiff"
    )
    if(EXISTS "${NEGAFLOW_SOURCE_TIFF_FIXTURE}")
        add_test(
            NAME native.scanner_to_working
            COMMAND negaflow_scanner_to_working_tests "${NEGAFLOW_SOURCE_TIFF_FIXTURE}"
        )
    else()
        add_test(NAME native.scanner_to_working COMMAND negaflow_scanner_to_working_tests)
    endif()

    add_executable(negaflow_colorsync_icm_parity_tests
        tests/Native.UnitTests/colorsync_icm_parity_tests.cpp
    )
    target_include_directories(
        negaflow_colorsync_icm_parity_tests
        PRIVATE
            "${CMAKE_CURRENT_SOURCE_DIR}/tests/fixtures/v1"
            "${CMAKE_CURRENT_SOURCE_DIR}/src/Native/imaging"
    )
    target_link_libraries(
        negaflow_colorsync_icm_parity_tests
        PRIVATE negaflow_imaging negaflow_color negaflow_core negaflow_project_options bcrypt
    )
    add_test(
        NAME native.colorsync_icm_parity
        COMMAND negaflow_colorsync_icm_parity_tests
    )

    add_executable(negaflow_colorsync_icm_develop_impact_tests
        tests/Native.UnitTests/colorsync_icm_develop_impact_tests.cpp
    )
    target_include_directories(
        negaflow_colorsync_icm_develop_impact_tests
        PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/tests/fixtures/v1"
    )
    target_link_libraries(
        negaflow_colorsync_icm_develop_impact_tests
        PRIVATE negaflow_imaging negaflow_color negaflow_project_options
    )
    add_test(
        NAME native.colorsync_icm_develop_impact
        COMMAND negaflow_colorsync_icm_develop_impact_tests
    )

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
        add_test(
            NAME cli.develop_negative_tiff_film_look
            COMMAND negaflow_cli --develop-negative-tiff
                "${NEGAFLOW_SOURCE_TIFF_FIXTURE}" 0.72 0.32 0.15 color
                film_scan velvia_50 0.73
        )
        set_tests_properties(
            cli.develop_negative_tiff_film_look
            PROPERTIES PASS_REGULAR_EXPRESSION
                # A film scan runs the Film Look as identity, so it adds no
                # statistics pass: scanner-to-working and develop only.
                "\"film_look_arguments_explicit\":true.*\"film_look_route\":\"identity\".*\"film_color_applied\":false.*\"film_acutance_applied\":false.*\"statistics_full_frame_scan_count\":2"
        )
        add_test(
            NAME cli.develop_negative_tiff_tone_film_look
            COMMAND negaflow_cli --develop-negative-tiff
                "${NEGAFLOW_SOURCE_TIFF_FIXTURE}" 0.72 0.32 0.15 color
                0.75 0.35 0.30 -0.25 0.20 0.40
                film_scan velvia_50 0.73
        )
        set_tests_properties(
            cli.develop_negative_tiff_tone_film_look
            PROPERTIES PASS_REGULAR_EXPRESSION
                # Tone adds the one extra pass; the identity Film Look adds none.
                "\"film_look_arguments_explicit\":true.*\"film_look_route\":\"identity\".*\"film_color_applied\":false.*\"film_acutance_applied\":false.*\"tone_arguments_explicit\":true.*\"statistics_full_frame_scan_count\":3"
        )
        add_test(
            NAME native.develop_export_abi
            COMMAND negaflow_develop_export_abi_tests "${NEGAFLOW_SOURCE_TIFF_FIXTURE}"
        )
        add_test(
            NAME cli.export_developed_tiff_film_look
            COMMAND ${CMAKE_COMMAND}
                "-DCLI=$<TARGET_FILE:negaflow_cli>"
                "-DSOURCE=${NEGAFLOW_SOURCE_TIFF_FIXTURE}"
                "-DOUTPUT_DIR=${CMAKE_CURRENT_BINARY_DIR}/verification/$<CONFIG>"
                -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/CMake/verify_developed_tiff_film_look.cmake"
        )
    else()
        add_test(NAME native.wic_tiff_decode COMMAND negaflow_wic_tiff_decoder_tests)
        # Without the local fixture the ABI still gets its argument and refusal
        # contract checked; only the full develop is skipped.
        add_test(
            NAME native.develop_export_abi
            COMMAND negaflow_develop_export_abi_tests
        )
    endif()
endif()
