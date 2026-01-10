cmake_minimum_required(VERSION 3.10)
project(FortranCallJuliaExamples LANGUAGES Fortran)

# ==============================================================================
# Examples Build Configuration
# ==============================================================================

# Check if we are part of the main build or standalone
if(TARGET fj_middleware)
    message(STATUS "Building examples as part of the main project.")
    set(MW_SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/../src/middleware.jl")
else(TARGET fj_middleware)
    message(STATUS "Building examples standalone.")
    
    # Try to find the library and headers
    # User should provide CMAKE_PREFIX_PATH pointing to install dir
    
    find_library(FJ_LIB NAMES fj_middleware REQUIRED)
    find_path(FJ_INCLUDE_DIR NAMES bridge.h REQUIRED)
    find_path(FJ_MOD_DIR NAMES julia_high_level.mod REQUIRED)
    
    message(STATUS "Found Library: ${FJ_LIB}")
    message(STATUS "Found Includes: ${FJ_INCLUDE_DIR}")
    message(STATUS "Found Modules: ${FJ_MOD_DIR}")

    # --- Find Julia (Required for linking) ---
    find_program(JULIA_EXECUTABLE julia DOC "Path to Julia executable")
    if(NOT JULIA_EXECUTABLE)
        message(FATAL_ERROR "Julia executable not found.")
    endif()

    execute_process(COMMAND ${JULIA_EXECUTABLE} -e "import Libdl; print(joinpath(Sys.BINDIR, Base.DATAROOTDIR, \"julia\", \"julia-config.jl\"))" OUTPUT_VARIABLE JULIA_CONFIG_SCRIPT)
    execute_process(COMMAND ${JULIA_EXECUTABLE} ${JULIA_CONFIG_SCRIPT} --ldflags OUTPUT_VARIABLE JULIA_LDFLAGS OUTPUT_STRIP_TRAILING_WHITESPACE)
    execute_process(COMMAND ${JULIA_EXECUTABLE} ${JULIA_CONFIG_SCRIPT} --ldlibs OUTPUT_VARIABLE JULIA_LDLIBS OUTPUT_STRIP_TRAILING_WHITESPACE)
    
    # Cleanup flags
    string(REPLACE "\n" " " JULIA_LDFLAGS "${JULIA_LDFLAGS}")
    string(REPLACE " " ";" JULIA_LDFLAGS "${JULIA_LDFLAGS}")
    string(REPLACE "'" "" JULIA_LDFLAGS "${JULIA_LDFLAGS}")
    string(REPLACE "\n" " " JULIA_LDLIBS "${JULIA_LDLIBS}")
    string(REPLACE " " ";" JULIA_LDLIBS "${JULIA_LDLIBS}")
    string(REPLACE "'" "" JULIA_LDLIBS "${JULIA_LDLIBS}")
    
    message(STATUS "Julia LDFLAGS: ${JULIA_LDFLAGS}")
    message(STATUS "Julia LDLIBS: ${JULIA_LDLIBS}")

    # Create an interface target to match the internal one
    add_library(fj_middleware UNKNOWN IMPORTED)
    set_target_properties(fj_middleware PROPERTIES
        IMPORTED_LOCATION "${FJ_LIB}"
        INTERFACE_INCLUDE_DIRECTORIES "${FJ_INCLUDE_DIR};${FJ_MOD_DIR}"
        INTERFACE_LINK_LIBRARIES "${JULIA_LDLIBS}"
        INTERFACE_LINK_OPTIONS "${JULIA_LDFLAGS}"
    )
    
    # We assume standard install layout where middleware.jl is in share/FortranCallJulia
    # or user specified it.
    find_file(MW_SOURCE middleware.jl PATHS 
        ${FJ_INCLUDE_DIR}/../share/FortranCallJulia
        ${FJ_INCLUDE_DIR}/../src # Fallback for build tree
        REQUIRED
    )
endif()

# Helper macro for adding examples
macro(add_fj_example name source)
    add_executable(${name} ${source})
    
    # Link against the middleware library
    target_link_libraries(${name} PRIVATE fj_middleware)
    
    # Standard Fortran Flags
    target_compile_options(${name} PRIVATE -fno-underscoring)
    
    # Ensure modules are found (if using modules from build tree)
    if(TARGET fj_middleware)
        get_target_property(MOD_DIR fj_middleware Fortran_MODULE_DIRECTORY)
        if(MOD_DIR)
            target_include_directories(${name} PRIVATE ${MOD_DIR})
        endif()
    endif()

    # Post-build: Copy middleware.jl to the executable's directory
    # This is needed for Development Mode (loading .jl source)
    add_custom_command(TARGET ${name} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
        ${MW_SOURCE}
        ${CMAKE_CURRENT_BINARY_DIR}/middleware.jl
        COMMENT "Copying middleware.jl to ${name} directory"
    )
endmacro()

# ==============================================================================
# Define Examples
# ==============================================================================

add_fj_example(ex01_hello       01_hello.f90)
add_fj_example(ex02_math_oop    02_math_oop.f90)
add_fj_example(ex03_performance 03_performance.f90)
add_fj_example(ex04_arrays      04_arrays.f90)
add_fj_example(ex05_errors      05_errors.f90)
# Example 6: Sysimage Loading
add_fj_example(ex06_sysimage 06_sysimage.f90)

# Example 7: Linear Algebra
add_fj_example(ex07_linear_algebra 07_linear_algebra.f90)

# Example 8: Special Functions
add_fj_example(ex08_special_functions 08_special_functions.f90)

# Example 9: Complex Workflow
add_fj_example(ex09_complex_workflow 09_complex_workflow.f90)

# Example 10: External Script
add_fj_example(ex10_external_script 10_external_script.f90)
add_custom_command(TARGET ex10_external_script POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
    ${CMAKE_CURRENT_SOURCE_DIR}/user_script.jl
    ${CMAKE_CURRENT_BINARY_DIR}/user_script.jl
    COMMENT "Copying user_script.jl to ex10 directory"
)

