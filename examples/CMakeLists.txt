cmake_minimum_required(VERSION 3.13)
project(FortranCallJuliaExamples LANGUAGES Fortran C)

# ==============================================================================
# Examples Build Configuration
# ==============================================================================

if(TARGET fj_middleware)
    # Built as part of main project: the Julia runtime is the in-repo package
    set(FJ_RUNTIME_SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/../src/FortranBridge")
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

    # Installed SDK: the FortranBridge package directory (contains Project.toml)
    find_path(FJ_RUNTIME_SOURCE
        NAMES Project.toml
        PATHS "${FJ_INCLUDE_DIR}/../share/FortranCallJulia/FortranBridge"
              "${FJ_INCLUDE_DIR}/../share/FortranBridge"
        NO_DEFAULT_PATH
    )
    if(NOT FJ_RUNTIME_SOURCE)
        message(FATAL_ERROR "FortranBridge Julia package (Project.toml) not found in the installed SDK")
    endif()
endif()

# ==============================================================================
# Helper Macro
# ==============================================================================

# Serialized copy of the shared Julia runtime (the FortranBridge package) plus
# examples_lib.jl: one custom target performs all copies; fj_init_ex resolves
# the package via the exe-adjacent probe (FortranBridge/Project.toml next to
# the executable). Per-example POST_BUILD copies of the same paths raced
# under -jN ("Error copying directory").
if(NOT TARGET fj_copy_runtime)
add_custom_target(fj_copy_runtime
COMMAND ${CMAKE_COMMAND} -E copy_directory
${FJ_RUNTIME_SOURCE}
${CMAKE_CURRENT_BINARY_DIR}/FortranBridge
COMMAND ${CMAKE_COMMAND} -E copy_if_different
${CMAKE_CURRENT_SOURCE_DIR}/examples_lib.jl
${CMAKE_CURRENT_BINARY_DIR}/examples_lib.jl
)
endif()
macro(add_fj_example name source)
    add_executable(${name} ${source})
    target_link_libraries(${name} PRIVATE fj_middleware)
    # -fno-underscoring and -cpp are GNU-only flags; non-GNU compilers need
    # their own equivalents (e.g. -fpp instead of -cpp for Intel).
    if(CMAKE_Fortran_COMPILER_ID STREQUAL "GNU")
        target_compile_options(${name} PRIVATE -fno-underscoring)
    endif()

    # If built in-tree, add module dir
    if(TARGET fj_middleware)
        get_target_property(MOD_DIR fj_middleware Fortran_MODULE_DIRECTORY)
        if(MOD_DIR)
            target_include_directories(${name} PRIVATE ${MOD_DIR})
        endif()
    endif()

    add_dependencies(${name} fj_copy_runtime)
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
add_fj_example(ex_init_options          03_deployment/ex_init_options.f90)

# ==============================================================================
# 4. Performance (Optimization)
# ==============================================================================

# 4.1. Startup Comparison (JIT vs AOT)
# Target A: Dynamic (JIT)
add_fj_example(ex_perf_startup_jit      04_performance/1_jit_vs_aot.f90)
if(CMAKE_Fortran_COMPILER_ID STREQUAL "GNU")
    target_compile_options(ex_perf_startup_jit PRIVATE -cpp)
endif()

# Target B: Static (Compiled Library)
# We only build this if the user has built the library in 03_deployment/2_compiled_library
set(MYLIB_DIR "${CMAKE_CURRENT_SOURCE_DIR}/03_deployment/2_compiled_library/dist/lib")
find_library(MYLIB_LIB NAMES mylib MyLib PATHS ${MYLIB_DIR} NO_DEFAULT_PATH)

if(MYLIB_LIB)
    message(STATUS "Found MyLib (Compiled Mode): ${MYLIB_LIB}")
    add_executable(ex_perf_startup_aot 04_performance/1_jit_vs_aot.f90)
    target_link_libraries(ex_perf_startup_aot PRIVATE ${MYLIB_LIB} fj_middleware)
    target_compile_options(ex_perf_startup_aot PRIVATE -DCOMPILED_MODE)
    # -fno-underscoring / -cpp are GNU-only; non-GNU compilers need their own.
    if(CMAKE_Fortran_COMPILER_ID STREQUAL "GNU")
        target_compile_options(ex_perf_startup_aot PRIVATE -fno-underscoring -cpp)
    endif()
    # Include headers for MyLib if any (implicit in this case)

    # Same in-tree module-dir wiring the add_fj_example macro applies;
    # this target was never compiled before (MyLib was not found), so it
    # silently lacked it.
    if(TARGET fj_middleware)
        get_target_property(MOD_DIR fj_middleware Fortran_MODULE_DIRECTORY)
        if(MOD_DIR)
            target_include_directories(ex_perf_startup_aot PRIVATE ${MOD_DIR})
        endif()
    endif()

    add_dependencies(ex_perf_startup_aot fj_copy_runtime)
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
    # -fno-underscoring is GNU-only; non-GNU compilers need their own flags.
    if(CMAKE_Fortran_COMPILER_ID STREQUAL "GNU")
        target_compile_options(ex_hpc_mpi_bootstrap PRIVATE -fno-underscoring)
    endif()

    # In-tree module support
    if(TARGET fj_middleware)
        get_target_property(MOD_DIR fj_middleware Fortran_MODULE_DIRECTORY)
        if(MOD_DIR)
            target_include_directories(ex_hpc_mpi_bootstrap PRIVATE ${MOD_DIR})
        endif()
    endif()

    # Runtime files are covered by the shared fj_copy_runtime target
    add_dependencies(ex_hpc_mpi_bootstrap fj_copy_runtime)
else()
    message(STATUS "MPI Not Found: Skipping ex_hpc_mpi_bootstrap")
endif()

# ==============================================================================
# 6. SciML-Style Integration (Wave B)
# ==============================================================================

# Fortran bind(c) RHS wrapped into a Julia-side callable f(du,u,p,t)
add_fj_example(ex_sciml_callback        05_sciml/1_callback.f90)

# Batch extraction: 1-based element / getproperty / bulk to_fortran
add_fj_example(ex_sciml_batch_data      05_sciml/2_batch_data.f90)

# End-to-end acceptance demo: Fortran bind(c) RHS -> Main.FJ_CALLBACK ->
# OrdinaryDiffEq solve -> extraction of the final state vs analytic solution
add_fj_example(ex_sciml_demo            05_sciml/3_sciml_demo.f90)

# ==============================================================================
# 7. Capstone: Reacting Flow (Clawpack transport + embedded Julia chemistry)
# ==============================================================================
# The transport engine is the vendored Clawpack classic 1D kernel (see
# third_party/clawpack1d/SOURCES.md); it only exists in the in-tree examples
# build. Chemistry arrives in later commits via the bridge -- this commit
# validates the transport engine alone (Sod vs exact Riemann solution).
if(TARGET clawpack1d)
    add_fj_example(ex_reacting_flow      06_capstone/1_reacting_flow.f90)
    target_link_libraries(ex_reacting_flow PRIVATE clawpack1d)
endif()
