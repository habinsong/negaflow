function(negaflow_enable_strict_warnings target_name)
    if(MSVC)
        target_compile_options(
            ${target_name}
            INTERFACE
                /W4
                /WX
                /permissive-
                /Zc:__cplusplus
                /Zc:preprocessor
                /utf-8
                /fp:precise
                /sdl
                /guard:cf
        )
        target_link_options(
            ${target_name}
            INTERFACE
                /DYNAMICBASE
                /NXCOMPAT
                /guard:cf
        )
    else()
        message(FATAL_ERROR "Negaflow Windows currently supports the pinned MSVC toolchain only")
    endif()
endfunction()
