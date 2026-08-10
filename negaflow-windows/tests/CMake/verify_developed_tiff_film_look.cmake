cmake_minimum_required(VERSION 3.30)

foreach(required_variable IN ITEMS CLI SOURCE OUTPUT_DIR)
    if(NOT DEFINED ${required_variable})
        message(FATAL_ERROR "Missing ${required_variable}")
    endif()
endforeach()

file(MAKE_DIRECTORY "${OUTPUT_DIR}")
set(identity_output "${OUTPUT_DIR}/developed-film-look-identity.tiff")
set(tone_output "${OUTPUT_DIR}/developed-film-look-tone.tiff")
set(active_output "${OUTPUT_DIR}/developed-film-look-active.tiff")
set(missing_source "${OUTPUT_DIR}/definitely-missing-source.tiff")

function(clean_outputs)
    file(REMOVE
        "${identity_output}"
        "${tone_output}"
        "${active_output}"
        "${missing_source}"
    )
endfunction()

function(fail_verification detail)
    clean_outputs()
    message(FATAL_ERROR "${detail}")
endfunction()

clean_outputs()
execute_process(
    COMMAND "${CLI}" --export-developed-tiff16
        "${SOURCE}" "${identity_output}" 0.72 0.32 0.15 color
    RESULT_VARIABLE identity_result
    OUTPUT_VARIABLE identity_report
    ERROR_VARIABLE identity_error
)
if(NOT identity_result EQUAL 0)
    fail_verification("Identity export failed: ${identity_error}")
endif()

execute_process(
    COMMAND "${CLI}" --export-developed-tiff16
        "${SOURCE}" "${tone_output}" 0.72 0.32 0.15 color
        0.75 0.35 0.30 -0.25 0.20 0.40
    RESULT_VARIABLE tone_result
    OUTPUT_VARIABLE tone_report
    ERROR_VARIABLE tone_error
)
if(NOT tone_result EQUAL 0)
    fail_verification("Tone-only export failed: ${tone_error}")
endif()

execute_process(
    COMMAND "${CLI}" --export-developed-tiff16
        "${SOURCE}" "${active_output}" 0.72 0.32 0.15 color
        0.75 0.35 0.30 -0.25 0.20 0.40
        film_scan velvia_50 0.73
    RESULT_VARIABLE active_result
    OUTPUT_VARIABLE active_report
    ERROR_VARIABLE active_error
)
if(NOT active_result EQUAL 0)
    fail_verification("Active Film Look export failed: ${active_error}")
endif()

foreach(required_report_fragment IN ITEMS
    "\"status\":\"ok\""
    "\"source_sha256_mode\":\"off\""
    "\"artifact_sha256_mode\":\"off\""
    "\"exposure_applied\":true"
    "\"arguments_explicit\":true"
    "\"route\":\"identity\""
    "\"color_applied\":false"
    "\"acutance_applied\":false"
)
    string(FIND "${active_report}" "${required_report_fragment}" fragment_position)
    if(fragment_position EQUAL -1)
        fail_verification("Missing report fragment: ${required_report_fragment}")
    endif()
endforeach()

string(FIND "${active_report}" "\"tone_adjust\"" tone_position)
string(FIND "${active_report}" "\"film_look\"" film_look_position)
string(FIND
    "${active_report}"
    "\"output_convert_encode_verify_publish\""
    output_position
)
if(tone_position EQUAL -1 OR film_look_position EQUAL -1 OR
   output_position EQUAL -1 OR NOT tone_position LESS film_look_position OR
   NOT film_look_position LESS output_position)
    fail_verification("Pipeline report stages are out of order")
endif()

if(NOT EXISTS "${identity_output}" OR NOT EXISTS "${tone_output}" OR
   NOT EXISTS "${active_output}")
    fail_verification("An export artifact was not published")
endif()
file(SIZE "${identity_output}" identity_bytes)
file(SIZE "${tone_output}" tone_bytes)
file(SIZE "${active_output}" active_bytes)
if(identity_bytes EQUAL 0 OR tone_bytes EQUAL 0 OR active_bytes EQUAL 0)
    fail_verification("An export artifact is empty")
endif()
execute_process(
    COMMAND "${CMAKE_COMMAND}" -E compare_files
        "${tone_output}" "${active_output}"
    RESULT_VARIABLE comparison_result
)
if(NOT comparison_result EQUAL 0)
    fail_verification("A film-scan Film Look changed the tone-matched TIFF artifact")
endif()

execute_process(
    COMMAND "${CLI}" --export-developed-tiff16
        "${missing_source}" "${active_output}" 0.72 0.32 0.15 color
        rendered_digital velvia_50 0.73
    RESULT_VARIABLE invalid_result
    OUTPUT_VARIABLE invalid_output
    ERROR_VARIABLE invalid_error
)
string(FIND
    "${invalid_error}"
    "\"code\":\"negative_develop_requires_film_scan_source\""
    invalid_error_position
)
if(NOT invalid_result EQUAL 2 OR invalid_error_position EQUAL -1)
    fail_verification("Rendered-digital negative input was not rejected before I/O")
endif()

clean_outputs()
