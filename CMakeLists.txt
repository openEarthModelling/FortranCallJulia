cmake_minimum_required(VERSION 3.13)
project(FortranCallJulia VERSION 0.1.0 LANGUAGES C Fortran)

# ==============================================================================
# Options
# ==============================================================================
option(BUILD_EXAMPLES "Build the example applications" OFF)
option(FJ_BUILD_SYSIMAGE "Build libfj_sysimage via PackageCompiler" OFF)

# ==============================================================================
# Find Julia and Configuration
# ==============================================================================
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
include(FcjJuliaDiscovery)

# Discovery and the 1.12.x pin are load-bearing for the whole build, not
# just the sysimage: the bridge embeds libjulia 1.12.7 and the acceptance
# baselines are only meaningful against that runtime.
fcj_find_julia()
fcj_require_julia_1_12()

message(STATUS "Found Julia: ${JULIA_EXECUTABLE} -> ${FCJ_JULIA_REAL}")

# ==============================================================================
# Core Library (Fortran-Julia Middleware)
# ==============================================================================
add_library(fcj_middleware STATIC
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

# Namespaced alias: add_subdirectory/FetchContent consumers and the
# installed Config package all expose fcj::fcj_middleware (the alias is
# linkable from a consumer's toplevel; verified, that is how fmt/Catch2
# style projects are consumed via FetchContent).
add_library(fcj::fcj_middleware ALIAS fcj_middleware)

# Set Include Directories (Public so consumers inherit it)
target_include_directories(fcj_middleware PUBLIC 
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/src>
    $<INSTALL_INTERFACE:include>
)

# Apply Julia C Flags to bridge.c. FCJ_JULIA_REAL already resolved any
# juliaup shim; the compile-time JULIA_BINDIR must be the real bin dir.
get_filename_component(JULIA_BINDIR "${FCJ_JULIA_REAL}" DIRECTORY)
target_compile_definitions(fcj_middleware PRIVATE JULIA_BINDIR="${JULIA_BINDIR}")

target_compile_options(fcj_middleware PRIVATE
    $<$<COMPILE_LANGUAGE:C>:${FCJ_JULIA_CFLAGS}>
)

# -fno-underscoring is GNU-only (gfortran): it disables gfortran's default
# trailing-underscore name mangling so C-side symbol lookups match.
if(CMAKE_Fortran_COMPILER_ID STREQUAL "GNU")
    target_compile_options(fcj_middleware PRIVATE
        $<$<COMPILE_LANGUAGE:Fortran>:-fno-underscoring>
    )
endif()

# Link Options
target_link_options(fcj_middleware INTERFACE ${FCJ_JULIA_LDFLAGS})
target_link_libraries(fcj_middleware INTERFACE ${FCJ_JULIA_LDLIBS})

# Fortran Module Output Directory
set_target_properties(fcj_middleware PROPERTIES 
    Fortran_MODULE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/modules
)

# ==============================================================================
# Installation
# ==============================================================================
include(GNUInstallDirs)

# Install Library
install(TARGETS fcj_middleware
    EXPORT FortranCallJuliaTargets
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

# find_package(FortranCallJulia) support: exported targets plus Config
# files. The Config re-runs Julia discovery on the consumer's machine, so
# the installed package is not tied to this build's libjulia paths.
set(FJ_CMAKE_INSTALL_DIR ${CMAKE_INSTALL_LIBDIR}/cmake/FortranCallJulia)
include(CMakePackageConfigHelpers)
configure_package_config_file(
    cmake/FortranCallJuliaConfig.cmake.in
    "${CMAKE_CURRENT_BINARY_DIR}/FortranCallJuliaConfig.cmake"
    INSTALL_DESTINATION ${FJ_CMAKE_INSTALL_DIR}
)
write_basic_package_version_file(
    "${CMAKE_CURRENT_BINARY_DIR}/FortranCallJuliaConfigVersion.cmake"
    VERSION ${PROJECT_VERSION}
    COMPATIBILITY SameMajorVersion
)
install(EXPORT FortranCallJuliaTargets
    NAMESPACE fcj::
    FILE FortranCallJuliaTargets.cmake
    DESTINATION ${FJ_CMAKE_INSTALL_DIR}
)
install(FILES
    "${CMAKE_CURRENT_BINARY_DIR}/FortranCallJuliaConfig.cmake"
    "${CMAKE_CURRENT_BINARY_DIR}/FortranCallJuliaConfigVersion.cmake"
    cmake/FcjJuliaDiscovery.cmake
    DESTINATION ${FJ_CMAKE_INSTALL_DIR}
)

# ==============================================================================
# AOT Sysimage via PackageCompiler (Optional)
# ==============================================================================
if(FJ_BUILD_SYSIMAGE)
    # The 1.12.x pin was already hard-enforced at configure time
    # (fcj_require_julia_1_12 above): the sysimage must be built by the
    # same minor version that embeds it, and a juliaup shim defaulting to
    # another version would produce a load-crashing artifact.
    set(JULIA_SYSIMAGE_EXE "${FCJ_JULIA_REAL}")

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

    add_custom_target(fcj_sysimage
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
    add_subdirectory(examples)
endif()