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
                # Release 에도 디버그 정보를 남깁니다. 사용자 기계에서 난 액세스 위반의
                # 주소(RVA)를 함수·줄로 되돌리려면 PDB 가 있어야 합니다 — 2026-08-20
                # 자동 레벨 크래시(0xc0000005 @ Negaflow.Native.dll+0x1546cb)를 PDB 가
                # 없어서 못 짚었습니다. /Zi 는 실행 성능에 영향이 없습니다.
                $<$<CONFIG:Release>:/Zi>
        )
        target_link_options(
            ${target_name}
            INTERFACE
                /DYNAMICBASE
                /NXCOMPAT
                /guard:cf
                # /DEBUG 는 PDB 를 만들고, /OPT:REF,ICF 로 Release 최적화를 되돌립니다
                # (/DEBUG 는 기본으로 그 둘을 끄기 때문입니다).
                $<$<CONFIG:Release>:/DEBUG>
                $<$<CONFIG:Release>:/OPT:REF>
                # /OPT:ICF 는 같은 본문의 함수를 하나로 접습니다. 크래시 스택에서 어느
                # 람다였는지 알 수 없게 되므로 켜지 않습니다.
                # MAP 은 함수마다 RVA 를 적어 줍니다. 크래시 로그의 오프셋을 이름으로
                # 되돌리는 가장 확실한 길입니다(PDB 가 이름을 못 낼 때도 됩니다).
                $<$<CONFIG:Release>:/MAP>
        )
    else()
        message(FATAL_ERROR "Negaflow Windows currently supports the pinned MSVC toolchain only")
    endif()
endfunction()
