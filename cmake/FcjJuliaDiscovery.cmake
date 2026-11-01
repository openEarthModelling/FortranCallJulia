# Shared Julia discovery for the FortranCallJulia build and its installed
# Config package. Installed alongside FortranCallJuliaConfig.cmake so a
# find_package() consumer runs the exact same discovery as the in-tree
# build.
#
# fcj_find_julia()
#   Finds the interpreter (find_program honors -DJULIA_EXECUTABLE), resolves
#   symlinks/juliaup shims to the real binary, and asks julia-config.jl for
#   the matching flags. Sets in the caller's scope:
#     JULIA_EXECUTABLE  as found (cache, overridable)
#     FCJ_JULIA_REAL    symlink-resolved interpreter path
#     FCJ_JULIA_CFLAGS / FCJ_JULIA_LDFLAGS / FCJ_JULIA_LDLIBS  flag lists
#
# fcj_require_julia_1_12()
#   FATAL_ERROR unless the resolved Julia reports 1.12.x. The bridge embeds
#   libjulia 1.12.7 and every acceptance baseline is pinned to that runtime;
#   a juliaup shim silently defaulting to a newer minor once masqueraded as
#   a bridge regression, so the check is explicit and load-bearing.

function(fcj_find_julia)
    find_program(JULIA_EXECUTABLE julia DOC "Path to Julia executable")
    if(NOT JULIA_EXECUTABLE)
        message(FATAL_ERROR
            "Julia executable not found. Please ensure 'julia' is in your PATH.")
    endif()

    # Resolve shims/symlinks: flags and version checks must describe the
    # real runtime, not the juliaup indirection in front of it.
    get_filename_component(FCJ_JULIA_REAL "${JULIA_EXECUTABLE}" REALPATH)

    execute_process(
        COMMAND ${FCJ_JULIA_REAL} -e "import Libdl; print(joinpath(Sys.BINDIR, Base.DATAROOTDIR, \"julia\", \"julia-config.jl\"))"
        OUTPUT_VARIABLE _fcj_config_script
        OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE _fcj_res
    )
    if(NOT _fcj_res EQUAL 0)
        message(FATAL_ERROR
            "Failed to locate julia-config.jl via \"${FCJ_JULIA_REAL}\".")
    endif()

    foreach(_fcj_pair "cflags;FCJ_JULIA_CFLAGS" "ldflags;FCJ_JULIA_LDFLAGS" "ldlibs;FCJ_JULIA_LDLIBS")
        list(GET _fcj_pair 0 _fcj_flag)
        list(GET _fcj_pair 1 _fcj_var)
        execute_process(
            COMMAND ${FCJ_JULIA_REAL} ${_fcj_config_script} --${_fcj_flag}
            OUTPUT_VARIABLE _fcj_out
            OUTPUT_STRIP_TRAILING_WHITESPACE
            RESULT_VARIABLE _fcj_res
        )
        if(NOT _fcj_res EQUAL 0)
            message(FATAL_ERROR "julia-config.jl failed for --${_fcj_flag}.")
        endif()
        # Same normalization the build has always used: flatten newlines,
        # drop shell quoting, and split into a CMake list on whitespace.
        string(REPLACE "\n" " " _fcj_out "${_fcj_out}")
        string(REPLACE "'" "" _fcj_out "${_fcj_out}")
        string(REPLACE " " ";" _fcj_out "${_fcj_out}")
        set(${_fcj_var} "${_fcj_out}" PARENT_SCOPE)
    endforeach()

    set(FCJ_JULIA_REAL "${FCJ_JULIA_REAL}" PARENT_SCOPE)
endfunction()

function(fcj_require_julia_1_12)
    execute_process(
        COMMAND ${FCJ_JULIA_REAL} --version
        OUTPUT_VARIABLE _fcj_version
        OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE _fcj_res
    )
    if(NOT _fcj_res EQUAL 0)
        message(FATAL_ERROR
            "Failed to run \"${FCJ_JULIA_REAL} --version\".")
    endif()
    if(NOT _fcj_version MATCHES "^julia version 1\\.12\\.")
        message(FATAL_ERROR
            "FortranCallJulia embeds and links libjulia 1.12.x (validated on "
            "1.12.7), but \"${FCJ_JULIA_REAL} --version\" reported: ${_fcj_version}\n"
            "Point -DJULIA_EXECUTABLE at a self-contained 1.12.x Julia "
            "(not the juliaup shim).")
    endif()
endfunction()
