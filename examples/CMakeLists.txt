cmake_minimum_required(VERSION 3.13)
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

# Serialized copy of shared Julia runtime sources: per-example POST_BUILD
# copies of the same paths raced under -jN ("Error copying directory").
if(NOT TARGET fj_copy_middleware)
add_custom_target(fj_copy_middleware
COMMAND ${CMAKE_COMMAND} -E copy_if_different
${MW_SOURCE}
${CMAKE_CURRENT_BINARY_DIR}/middleware.jl
COMMAND ${CMAKE_COMMAND} -E copy_directory
${CMAKE_CURRENT_SOURCE_DIR}/../src/middleware
${CMAKE_CURRENT_BINARY_DIR}/middleware
COMMAND ${CMAKE_COMMAND} -E copy_if_different
${CMAKE_CURRENT_SOURCE_DIR}/examples_lib.jl
${CMAKE_CURRENT_BINARY_DIR}/examples_lib.jl
)
endif()
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

    add_dependencies(${name} fj_copy_middleware)
endmacro()

# ==============================================================================
# 1. Basics (Start Here)
# ==============================================================================

add_fj_example(ex01_quickstart          01_basics/1_quickstart.f90)
add_fj_example(ex02_zero_copy_arrays    01_basics/2_zero_copy_arrays.f90)
add_fj_example(ex03_data_structures     01_basics/3_data_structures.f90)

# ==============================================================================
# 2. Intermediate (Practical Usage)
# ==============================================================================

add_fj_example(ex_inter_math_operations 02_intermediate/1_math_operations.f90)
add_fj_example(ex_inter_kwargs          02_intermediate/2_kwargs.f90)

# ==============================================================================
# 3. Deployment (Production Ready)
# ==============================================================================

add_fj_example(ex_deploy_sysimage       03_deployment/1_custom_sysimage.f90)

# ==============================================================================
# 4. Performance (Optimization)
# ==============================================================================

# 4.1. Startup Comparison (JIT vs AOT)
# Target A: Dynamic (JIT)
add_fj_example(ex_perf_startup_jit      04_performance/1_jit_vs_aot.f90)
target_compile_options(ex_perf_startup_jit PRIVATE -cpp)

# Target B: Static (Compiled Library)
# We only build this if the user has built the library in 03_deployment/2_compiled_library
set(MYLIB_DIR "${CMAKE_CURRENT_SOURCE_DIR}/03_deployment/2_compiled_library/dist/lib")
find_library(MYLIB_LIB NAMES MyLib PATHS ${MYLIB_DIR} NO_DEFAULT_PATH)

if(MYLIB_LIB)
    message(STATUS "Found MyLib (Compiled Mode): ${MYLIB_LIB}")
    add_executable(ex_perf_startup_aot 04_performance/1_jit_vs_aot.f90)
    target_link_libraries(ex_perf_startup_aot PRIVATE ${MYLIB_LIB} fj_middleware)
    target_compile_options(ex_perf_startup_aot PRIVATE -fno-underscoring -DCOMPILED_MODE -cpp)
    # Include headers for MyLib if any (implicit in this case)
    
    # Standard copies
    add_custom_command(TARGET ex_perf_startup_aot POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
        ${MW_SOURCE}
        ${CMAKE_CURRENT_BINARY_DIR}/middleware.jl
    )
else()
    message(STATUS "MyLib not found. Skipping ex_perf_startup_aot. (Build 03_deployment/2_compiled_library first)")
endif()


add_fj_example(ex_perf_call_overhead    04_performance/2_call_overhead.f90)
add_fj_example(ex_perf_memory_transfer  04_performance/3_memory_transfer.f90)
add_fj_example(ex_perf_access_patterns  04_performance/4_access_patterns.f90)
add_fj_example(ex_perf_suite            04_performance/5_benchmark_suite.f90)

# ==============================================================================
# 5. HPC & Parallelism
# ==============================================================================

add_fj_example(ex_hpc_multithreading    05_hpc_parallel/1_multithreading.f90)

# MPI Example (Requires MPI)
option(BUILD_MPI_EXAMPLES "Build MPI examples" OFF)

if(BUILD_MPI_EXAMPLES)
    find_package(MPI)
endif()

if(BUILD_MPI_EXAMPLES AND MPI_Fortran_FOUND)
    message(STATUS "MPI Found: Enabling ex_hpc_mpi_bootstrap")
    add_executable(ex_hpc_mpi_bootstrap 05_hpc_parallel/2_mpi_bootstrap.f90)
    target_link_libraries(ex_hpc_mpi_bootstrap PRIVATE fj_middleware MPI::MPI_Fortran)
    target_compile_options(ex_hpc_mpi_bootstrap PRIVATE -fno-underscoring)
    
    # In-tree module support
    if(TARGET fj_middleware)
        get_target_property(MOD_DIR fj_middleware Fortran_MODULE_DIRECTORY)
        if(MOD_DIR)
            target_include_directories(ex_hpc_mpi_bootstrap PRIVATE ${MOD_DIR})
        endif()
    endif()

    # Copy runtime files
    add_custom_command(TARGET ex_hpc_mpi_bootstrap POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
        ${MW_SOURCE}
        ${CMAKE_CURRENT_BINARY_DIR}/middleware.jl
    )
    add_custom_command(TARGET ex_hpc_mpi_bootstrap POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_directory
        ${CMAKE_CURRENT_SOURCE_DIR}/../src/middleware
        ${CMAKE_CURRENT_BINARY_DIR}/middleware
    )
    add_custom_command(TARGET ex_hpc_mpi_bootstrap POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
        ${CMAKE_CURRENT_SOURCE_DIR}/examples_lib.jl
        ${CMAKE_CURRENT_BINARY_DIR}/examples_lib.jl
    )
else()
    message(STATUS "MPI Not Found: Skipping ex_hpc_mpi_bootstrap")
endif()