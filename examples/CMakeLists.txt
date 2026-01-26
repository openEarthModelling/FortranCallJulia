cmake_minimum_required(VERSION 3.10)
project(FortranCallJuliaExamples LANGUAGES Fortran C)

# ==============================================================================
# Examples Build Configuration
# ==============================================================================

if(TARGET fj_middleware)
    # Built as part of main project
    set(MW_SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/../src/middleware.jl")
else()
    # Standalone build (User installed SDK)
    find_library(FJ_LIB NAMES fj_middleware REQUIRED)
    find_path(FJ_INCLUDE_DIR NAMES bridge.h REQUIRED)
    find_path(FJ_MOD_DIR NAMES julia_high_level.mod REQUIRED)

    # Find Julia (Linker flags)
    find_program(JULIA_EXECUTABLE julia REQUIRED)
    execute_process(COMMAND ${JULIA_EXECUTABLE} -e "import Libdl; print(joinpath(Sys.BINDIR, Base.DATAROOTDIR, \"julia\", \"julia-config.jl\"))" OUTPUT_VARIABLE JULIA_CONFIG_SCRIPT)
    execute_process(COMMAND ${JULIA_EXECUTABLE} ${JULIA_CONFIG_SCRIPT} --ldflags OUTPUT_VARIABLE JULIA_LDFLAGS OUTPUT_STRIP_TRAILING_WHITESPACE)
    execute_process(COMMAND ${JULIA_EXECUTABLE} ${JULIA_CONFIG_SCRIPT} --ldlibs OUTPUT_VARIABLE JULIA_LDLIBS OUTPUT_STRIP_TRAILING_WHITESPACE)

    # Create imported target
    add_library(fj_middleware UNKNOWN IMPORTED)
    set_target_properties(fj_middleware PROPERTIES
        IMPORTED_LOCATION "${FJ_LIB}"
        INTERFACE_INCLUDE_DIRECTORIES "${FJ_INCLUDE_DIR};${FJ_MOD_DIR}"
        INTERFACE_LINK_LIBRARIES "${JULIA_LDLIBS} ${JULIA_LDFLAGS}"
    )
    
    find_file(MW_SOURCE middleware.jl PATHS ${FJ_INCLUDE_DIR}/../share/FortranCallJulia REQUIRED)
endif()

# ==============================================================================
# Helper Macro
# ==============================================================================

macro(add_fj_example name source)
    add_executable(${name} ${source})
    target_link_libraries(${name} PRIVATE fj_middleware)
    target_compile_options(${name} PRIVATE -fno-underscoring)

    # If built in-tree, add module dir
    if(TARGET fj_middleware)
        get_target_property(MOD_DIR fj_middleware Fortran_MODULE_DIRECTORY)
        if(MOD_DIR)
            target_include_directories(${name} PRIVATE ${MOD_DIR})
        endif()
    endif()

    # Copy middleware.jl (runtime requirement)
    add_custom_command(TARGET ${name} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
        ${MW_SOURCE}
        ${CMAKE_CURRENT_BINARY_DIR}/middleware.jl
    )

    # Copy middleware/ directory (runtime requirement for submodules)
    add_custom_command(TARGET ${name} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_directory
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/middleware
        ${CMAKE_CURRENT_BINARY_DIR}/middleware
    )

    # Copy examples_lib.jl (runtime requirement for examples)
    add_custom_command(TARGET ${name} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
        ${CMAKE_CURRENT_SOURCE_DIR}/examples_lib.jl
        ${CMAKE_CURRENT_BINARY_DIR}/examples_lib.jl
    )
endmacro()

# ==============================================================================
# Standard Examples (01 - 06)
# ==============================================================================

add_fj_example(ex01_basics          01_basics.f90)
add_fj_example(ex02_data_types      02_data_types.f90)
add_fj_example(ex03_integration     03_integration.f90)
add_fj_example(ex04_performance     04_performance.f90)
add_fj_example(ex05_sysimage        05_sysimage.f90)
add_fj_example(ex06_multithreading  06_multithreading.f90)
add_fj_example(ex08_generic_access  08_generic_access.f90)
add_fj_example(ex09_kwargs          09_kwargs.f90)
add_fj_example(ex11_modern_api      11_modern_api.f90)
add_fj_example(ex12_benchmark_overhead 12_benchmark_overhead.f90)

# ==============================================================================
# HPC Examples (MPI)
# ==============================================================================

option(BUILD_MPI_EXAMPLES "Build MPI examples" OFF)

if(BUILD_MPI_EXAMPLES)
    find_package(MPI)
endif()

if(BUILD_MPI_EXAMPLES AND MPI_Fortran_FOUND)
    message(STATUS "MPI Found: Enabling ex07_mpi_bootstrap")
    add_executable(ex07_mpi_bootstrap 07_mpi_bootstrap.f90)
    target_link_libraries(ex07_mpi_bootstrap PRIVATE fj_middleware MPI::MPI_Fortran)
    target_compile_options(ex07_mpi_bootstrap PRIVATE -fno-underscoring)
    
    # In-tree module support
    if(TARGET fj_middleware)
        get_target_property(MOD_DIR fj_middleware Fortran_MODULE_DIRECTORY)
        if(MOD_DIR)
            target_include_directories(ex07_mpi_bootstrap PRIVATE ${MOD_DIR})
        endif()
    endif()

    # Copy runtime files
    add_custom_command(TARGET ex07_mpi_bootstrap POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
        ${MW_SOURCE}
        ${CMAKE_CURRENT_BINARY_DIR}/middleware.jl
    )
    add_custom_command(TARGET ex07_mpi_bootstrap POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
        ${CMAKE_CURRENT_SOURCE_DIR}/examples_lib.jl
        ${CMAKE_CURRENT_BINARY_DIR}/examples_lib.jl
    )
else()
    message(STATUS "MPI Not Found: Skipping ex07_mpi_bootstrap")
endif()
