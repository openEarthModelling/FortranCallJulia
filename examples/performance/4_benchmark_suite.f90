program benchmark_suite
    use iso_c_binding
    use julia_high_level
    implicit none

    ! Benchmarking variables
    integer, parameter :: N_scalar = 100000
    integer, parameter :: N_matrix = 2000
    real(8) :: t_start, t_end
    real(8) :: t_baseline, t_fast, t_vector
    real(8) :: x, val
    real(8), allocatable :: mat(:,:)
    type(JuliaValue) :: j_val, j_mat, julia
    type(c_funptr) :: raw_ptr
    integer :: i
    
    ! Fast path pointer
    abstract interface
        function func_add(val) bind(c)
            import :: c_double
            real(c_double), value :: val
            real(c_double) :: func_add
        end function func_add
    end interface
    procedure(func_add), pointer :: c_add => null()

    print *, "=========================================================="
    print *, "      Fortran-Julia Bridge Performance Suite              "
    print *, "=========================================================="
    
    call julia_init()
    call julia_eval_string('include("examples_lib.jl")')
    call julia_eval_string('using .ExamplesLib')

    ! ---------------------------------------------------------
    ! Scenario 1: Call Overhead (Scalar Add)
    ! ---------------------------------------------------------
    print *, "Scenario 1: Call Latency (100k iters)"
    
    ! Baseline (Naive Call)
    x = 1.0d0
    call cpu_time(t_start)
    do i=1, N_scalar
        j_val = julia%call("perf_add_one", x)
        val = j_val%as_real()
    end do
    call cpu_time(t_end)
    t_baseline = t_end - t_start
    
    ! Fast Path
    raw_ptr = get_function_pointer("perf_add_one", "Float64", "Float64")
    call c_f_procpointer(raw_ptr, c_add)
    x = 1.0d0
    call cpu_time(t_start)
    do i=1, N_scalar
        val = c_add(x)
    end do
    call cpu_time(t_end)
    t_fast = t_end - t_start
    
    print "(A, F8.4, A, F6.1, A)", "  Standard Call: ", t_baseline, "s (1.0x)"
    print "(A, F8.4, A, F6.1, A)", "  Fast Path:     ", t_fast,     "s (", t_baseline/t_fast, "x)"
    print *

    ! ---------------------------------------------------------
    ! Scenario 2: Memory Bandwidth (Matrix Scale)
    ! ---------------------------------------------------------
    print *, "Scenario 2: Memory Bandwidth (2000x2000 Matrix)"
    allocate(mat(N_matrix, N_matrix))
    call random_number(mat)
    
    ! Warm-up JIT for perf_scale_matrix & perf_scale_matrix_bang
    ! (Using the actual data for simplicity)
    j_mat = julia_copy_array_2d(mat)
    j_val = julia%call("perf_scale_matrix", j_mat, 2.0d0)
    
    j_mat = julia_wrap_array_2d(mat, int(N_matrix, 8), int(N_matrix, 8))
    j_val = julia%call("perf_scale_matrix_bang", j_mat, 2.0d0)
    ! Note: in-place modified mat, but that's fine for benchmark, we re-run
    
    ! Deep Copy
    call cpu_time(t_start)
    j_mat = julia_copy_array_2d(mat) ! Copy to Julia
    j_val = julia%call("perf_scale_matrix", j_mat, 2.0d0) ! New array returned
    call cpu_time(t_end)
    t_baseline = t_end - t_start
    
    ! Zero Copy
    call cpu_time(t_start)
    j_mat = julia_wrap_array_2d(mat, int(N_matrix, 8), int(N_matrix, 8)) ! Wrap
    j_val = julia%call("perf_scale_matrix_bang", j_mat, 2.0d0) ! In-place
    call cpu_time(t_end)
    t_fast = t_end - t_start
    
    print "(A, F8.4, A, F6.1, A)", "  Deep Copy:     ", t_baseline, "s (1.0x)"
    print "(A, F8.4, A, F6.1, A)", "  Zero Copy:     ", t_fast,     "s (", t_baseline/t_fast, "x)"
    print *
    
    print *, "=========================================================="
    print *, "Conclusion: Use Fast Path for small loops,"
    print *, "            Use Zero-Copy/Batching for large data."
    print *, "=========================================================="

end program benchmark_suite