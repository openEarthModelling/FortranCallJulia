# Clawpack classic 1D kernel, vendored (see SOURCES.md). Pristine upstream
# files; the target exists only to compile and expose them. -fno-underscoring
# matches the in-tree examples that link this library (see the GNU-only flag
# gating comment in examples/CMakeLists.txt); bc1.f is fixed-form F77.
add_library(clawpack1d STATIC
    step1.f90
    limiter.f90
    philim.f90
    rp1_euler_with_efix.f90
    bc1.f
)
if(CMAKE_Fortran_COMPILER_ID STREQUAL "GNU")
    target_compile_options(clawpack1d PRIVATE -fno-underscoring)
    set_source_files_properties(bc1.f PROPERTIES COMPILE_OPTIONS "-std=legacy")
endif()
