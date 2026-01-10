cmake_minimum_required(VERSION 3.10)
project(FortranCallJulia LANGUAGES C Fortran)

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
message(STATUS "Julia Config Script: ${JULIA_CONFIG_SCRIPT}")

# We use the config script to get flags. 
# Note: The script outputs raw flags. We need to be careful with parsing if they are complex.
# For simplicity and robustness (as in the Makefile), we will capture the output and append it.

execute_process(COMMAND ${JULIA_EXECUTABLE} ${JULIA_CONFIG_SCRIPT} --cflags OUTPUT_VARIABLE JULIA_CFLAGS OUTPUT_STRIP_TRAILING_WHITESPACE)
execute_process(COMMAND ${JULIA_EXECUTABLE} ${JULIA_CONFIG_SCRIPT} --ldflags OUTPUT_VARIABLE JULIA_LDFLAGS OUTPUT_STRIP_TRAILING_WHITESPACE)
execute_process(COMMAND ${JULIA_EXECUTABLE} ${JULIA_CONFIG_SCRIPT} --ldlibs OUTPUT_VARIABLE JULIA_LDLIBS OUTPUT_STRIP_TRAILING_WHITESPACE)

# Clean up newlines if any and convert to list
string(REPLACE "\n" " " JULIA_CFLAGS "${JULIA_CFLAGS}")
string(REPLACE " " ";" JULIA_CFLAGS "${JULIA_CFLAGS}")
string(REPLACE "'" "" JULIA_CFLAGS "${JULIA_CFLAGS}")
string(REPLACE "\n" " " JULIA_LDFLAGS "${JULIA_LDFLAGS}")
string(REPLACE " " ";" JULIA_LDFLAGS "${JULIA_LDFLAGS}")
string(REPLACE "'" "" JULIA_LDFLAGS "${JULIA_LDFLAGS}")
string(REPLACE "\n" " " JULIA_LDLIBS "${JULIA_LDLIBS}")
string(REPLACE " " ";" JULIA_LDLIBS "${JULIA_LDLIBS}")
string(REPLACE "'" "" JULIA_LDLIBS "${JULIA_LDLIBS}")

message(STATUS "Julia CFLAGS: ${JULIA_CFLAGS}")
message(STATUS "Julia LDFLAGS: ${JULIA_LDFLAGS}")
message(STATUS "Julia LDLIBS: ${JULIA_LDLIBS}")

# ==============================================================================
# Core Library (Fortran-Julia Middleware)
# ==============================================================================
# Compile bridge.c with Julia flags
add_library(fj_middleware STATIC
    src/bridge.c
    src/julia_sdk.f90
)

# Set Include Directories
target_include_directories(fj_middleware PUBLIC 
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)

# Apply Julia C Flags to bridge.c
get_filename_component(JULIA_BINDIR ${JULIA_EXECUTABLE} DIRECTORY)
target_compile_definitions(fj_middleware PRIVATE JULIA_BINDIR="${JULIA_BINDIR}")

target_compile_options(fj_middleware PRIVATE 
    $<$<COMPILE_LANGUAGE:C>:${JULIA_CFLAGS}>
    $<$<COMPILE_LANGUAGE:Fortran>:-fno-underscoring> 
)

# Link Libraries (We likely need to link the interface or executable against Julia)
# For a static lib, we propagate the link flags to consumers
target_link_options(fj_middleware INTERFACE ${JULIA_LDFLAGS})
target_link_libraries(fj_middleware INTERFACE ${JULIA_LDLIBS})


# ==============================================================================
# Example Application
# ==============================================================================
add_executable(test_app examples/main.f90)

# Link against our middleware
target_link_libraries(test_app PRIVATE fj_middleware)

# Fortran specific flags for the app
target_compile_options(test_app PRIVATE -fno-underscoring)

# Ensure modules are found (CMake handles this for targets, but explicit checking helps)
set_target_properties(test_app PROPERTIES Fortran_MODULE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/modules)
set_target_properties(fj_middleware PROPERTIES Fortran_MODULE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/modules)

# ==============================================================================
# Copy middleware.jl to build dir for easy running
# ==============================================================================
add_custom_command(TARGET test_app POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy
    ${CMAKE_CURRENT_SOURCE_DIR}/src/middleware.jl
    ${CMAKE_CURRENT_BINARY_DIR}/middleware.jl
    COMMENT "Copying middleware.jl to binary directory"
)

# ==============================================================================
# AOT Sysimage Target
# ==============================================================================
add_custom_target(sysimage
    COMMAND ${JULIA_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/scripts/build_sysimage.jl
    WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
    COMMENT "Building Julia Sysimage (AOT)..."
)

# ==============================================================================
# AOT Test Application
# ==============================================================================
add_executable(test_aot examples/test_aot.f90)
target_link_libraries(test_aot PRIVATE fj_middleware)
target_compile_options(test_aot PRIVATE -fno-underscoring)
set_target_properties(test_aot PROPERTIES Fortran_MODULE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/modules)
