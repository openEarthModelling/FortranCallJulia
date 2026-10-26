cmake_minimum_required(VERSION 3.13)
project(FortranCallJulia LANGUAGES C Fortran)

# ==============================================================================
# Options
# ==============================================================================
option(BUILD_EXAMPLES "Build the example applications" OFF)
option(FJ_BUILD_SYSIMAGE "Build libfj_sysimage via PackageCompiler" OFF)

# ==============================================================================
# Find Julia and Configuration
# ==============================================================================
find_program(JULIA_EXECUTABLE julia DOC "Path to Julia executable")

if(NOT JULIA_EXECUTABLE)
    message(FATAL_ERROR "Julia executable not found. Please ensure 'julia' is in your PATH.")
endif()

message(STATUS "Found Julia: ${JULIA_EXECUTABLE}")

# Helper function to get Julia config
function(get_julia_config code output_var)
    execute_process(
        COMMAND ${JULIA_EXECUTABLE} -e "${code}"
        OUTPUT_VARIABLE _out
        OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE _res
    )
    if(NOT _res EQUAL 0)
        message(FATAL_ERROR "Failed to run Julia command for configuration.")
    endif()
    set(${output_var} "${_out}" PARENT_SCOPE)
endfunction()

# Get Flags from Julia
get_julia_config("import Libdl; print(joinpath(Sys.BINDIR, Base.DATAROOTDIR, \"julia\", \"julia-config.jl\"))" JULIA_CONFIG_SCRIPT)

execute_process(COMMAND ${JULIA_EXECUTABLE} ${JULIA_CONFIG_SCRIPT} --cflags OUTPUT_VARIABLE JULIA_CFLAGS OUTPUT_STRIP_TRAILING_WHITESPACE)
execute_process(COMMAND ${JULIA_EXECUTABLE} ${JULIA_CONFIG_SCRIPT} --ldflags OUTPUT_VARIABLE JULIA_LDFLAGS OUTPUT_STRIP_TRAILING_WHITESPACE)
execute_process(COMMAND ${JULIA_EXECUTABLE} ${JULIA_CONFIG_SCRIPT} --ldlibs OUTPUT_VARIABLE JULIA_LDLIBS OUTPUT_STRIP_TRAILING_WHITESPACE)

# Clean up flags
string(REPLACE "\n" " " JULIA_CFLAGS "${JULIA_CFLAGS}")
string(REPLACE " " ";" JULIA_CFLAGS "${JULIA_CFLAGS}")
string(REPLACE "'" "" JULIA_CFLAGS "${JULIA_CFLAGS}")
string(REPLACE "\n" " " JULIA_LDFLAGS "${JULIA_LDFLAGS}")
string(REPLACE " " ";" JULIA_LDFLAGS "${JULIA_LDFLAGS}")
string(REPLACE "'" "" JULIA_LDFLAGS "${JULIA_LDFLAGS}")
string(REPLACE "\n" " " JULIA_LDLIBS "${JULIA_LDLIBS}")
string(REPLACE " " ";" JULIA_LDLIBS "${JULIA_LDLIBS}")
string(REPLACE "'" "" JULIA_LDLIBS "${JULIA_LDLIBS}")

# ==============================================================================
# Core Library (Fortran-Julia Middleware)
# ==============================================================================
add_library(fj_middleware STATIC
    src/bridge/core.c
    src/bridge/memory.c
    src/bridge/dispatch.c
    src/bridge/accessors.c
    src/bridge/types.c
    src/bridge/arrays.c
    src/bridge/callbacks.c
    src/bridge/extract.c
    src/julia_binding.f90
    src/julia_sdk.f90
)

# Set Include Directories (Public so consumers inherit it)
target_include_directories(fj_middleware PUBLIC 
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/src>
    $<INSTALL_INTERFACE:include>
)

# Apply Julia C Flags to bridge.c
# Resolve symlinks first so a juliaup shim path resolves to the real
# versioned bin dir, then take its DIRECTORY.
get_filename_component(JULIA_BINDIR "${JULIA_EXECUTABLE}" REALPATH)
get_filename_component(JULIA_BINDIR "${JULIA_BINDIR}" DIRECTORY)
target_compile_definitions(fj_middleware PRIVATE JULIA_BINDIR="${JULIA_BINDIR}")

target_compile_options(fj_middleware PRIVATE 
    $<$<COMPILE_LANGUAGE:C>:${JULIA_CFLAGS}>
)

# -fno-underscoring is GNU-only (gfortran): it disables gfortran's default
# trailing-underscore name mangling so C-side symbol lookups match.
if(CMAKE_Fortran_COMPILER_ID STREQUAL "GNU")
    target_compile_options(fj_middleware PRIVATE
        $<$<COMPILE_LANGUAGE:Fortran>:-fno-underscoring>
    )
endif()

# Link Options
target_link_options(fj_middleware INTERFACE ${JULIA_LDFLAGS})
target_link_libraries(fj_middleware INTERFACE ${JULIA_LDLIBS})

# Fortran Module Output Directory
set_target_properties(fj_middleware PROPERTIES 
    Fortran_MODULE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/modules
)

# ==============================================================================
# Installation
# ==============================================================================
include(GNUInstallDirs)

# Install Library
install(TARGETS fj_middleware
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)

# Install Headers
install(FILES src/bridge/bridge.h DESTINATION ${CMAKE_INSTALL_INCLUDEDIR})

# Install Fortran Modules
install(DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/modules/
    DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
    FILES_MATCHING PATTERN "*.mod"
)

# Install the FortranBridge Julia package (Project.toml + src/). Lands in
# <prefix>/share/FortranCallJulia/FortranBridge, the location the standalone
# examples build probes via find_path(Project.toml).
install(DIRECTORY src/FortranBridge DESTINATION ${CMAKE_INSTALL_DATADIR}/FortranCallJulia)

# ==============================================================================
# AOT Sysimage via PackageCompiler (Optional)
# ==============================================================================
if(FJ_BUILD_SYSIMAGE)
    # The sysimage must be built by the same Julia minor version that embeds
    # it. Resolve shims/symlinks first: a juliaup shim defaulting to another
    # version (e.g. 1.13) reports that version and produces a load-crashing
    # artifact for the embedded 1.12.7 runtime.
    get_filename_component(JULIA_SYSIMAGE_EXE "${JULIA_EXECUTABLE}" REALPATH)
    execute_process(
        COMMAND ${JULIA_SYSIMAGE_EXE} --version
        RESULT_VARIABLE FJ_JULIA_VERSION_RES
        OUTPUT_VARIABLE FJ_JULIA_VERSION
        ERROR_VARIABLE FJ_JULIA_VERSION_ERR
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_STRIP_TRAILING_WHITESPACE
    )
    if(NOT FJ_JULIA_VERSION_RES EQUAL 0)
        message(FATAL_ERROR
            "FJ_BUILD_SYSIMAGE: failed to run \"${JULIA_SYSIMAGE_EXE} --version\": "
            "${FJ_JULIA_VERSION_ERR}")
    endif()
    if(NOT FJ_JULIA_VERSION MATCHES "^julia version 1\\.12\\.")
        message(FATAL_ERROR
            "FJ_BUILD_SYSIMAGE requires Julia 1.12.x, but \"${JULIA_SYSIMAGE_EXE} --version\" "
            "reported: ${FJ_JULIA_VERSION}\n"
            "The sysimage must be built by the same minor version that embeds it. "
            "Reconfigure with -DJULIA_EXECUTABLE pointing at a 1.12.x Julia, e.g. "
            "/home/redacted/julia-1.12.7/bin/julia (do not use the juliaup shim).")
    endif()

    # Scratch environment the image is built from (FortranBridge as a path dep
    # plus SciMLBase, OrdinaryDiffEq, PrecompileTools, PackageCompiler).
    # Created and instantiated once by scripts/install_sciml_env.jl.
    set(FJ_SYSIMAGE_ENV "${CMAKE_CURRENT_SOURCE_DIR}/scripts/sysimage_env")
    if(NOT EXISTS "${FJ_SYSIMAGE_ENV}/Project.toml")
        message(FATAL_ERROR
            "FJ_BUILD_SYSIMAGE: sysimage environment not found at ${FJ_SYSIMAGE_ENV}.\n"
            "Set it up once before building:\n"
            "  ${JULIA_SYSIMAGE_EXE} ${CMAKE_CURRENT_SOURCE_DIR}/scripts/install_sciml_env.jl")
    endif()

    # Platform-appropriate output extension.
    if(WIN32)
        set(FJ_SYSIMAGE_EXT ".dll")
    elseif(APPLE)
        set(FJ_SYSIMAGE_EXT ".dylib")
    else()
        set(FJ_SYSIMAGE_EXT ".so")
    endif()
    set(FJ_SYSIMAGE_OUTPUT "${CMAKE_BINARY_DIR}/libfj_sysimage${FJ_SYSIMAGE_EXT}")

    add_custom_target(fj_sysimage
        COMMAND ${JULIA_SYSIMAGE_EXE}
            --project=${FJ_SYSIMAGE_ENV}
            ${CMAKE_CURRENT_SOURCE_DIR}/scripts/build_sysimage.jl
            ${FJ_SYSIMAGE_OUTPUT}
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
        COMMENT "Building libfj_sysimage via PackageCompiler (minutes; downloads on first run)"
        VERBATIM
    )
endif()

# ==============================================================================
# Examples (Separated)
# ==============================================================================
if(BUILD_EXAMPLES)
    # Vendored Clawpack classic 1D kernel: transport engine of the reacting-
    # flow capstone example (only the examples need it).
    add_subdirectory(third_party/clawpack1d)
    add_subdirectory(examples)
endif()