program access_patterns
    use iso_c_binding
    use julia_high_level
    implicit none

    integer, parameter :: N = 1000000 ! 1 million elements
    real(8), allocatable :: arr(:)
    type(JuliaValue) :: wrapped_arr, res, julia
    type(c_funptr) :: raw_ptr
    real(8) :: t1, t2
    integer :: i
    real(8) :: val

    ! Interface for Fast Path Scalar Call
    abstract interface
        function func_sqrt(val) bind(c)
            import :: c_double
            real(c_double), value :: val
            real(c_double) :: func_sqrt
        end function func_sqrt
    end interface
    procedure(func_sqrt), pointer :: c_sqrt => null()

    print *, "--- Performance Test 3: Access Patterns (Loop vs Vectorized) ---"
    print *, "Array Size: ", N

    call julia_init()
    call julia_include_exe_relative("examples_lib.jl")
    call julia_eval_string('using .ExamplesLib')
    block
        type(JuliaValue) :: chk
        chk = julia_eval('isdefined(Main, :ExamplesLib)')
        if (.not. chk%as_logical()) error stop 'examples_lib.jl did not load: ExamplesLib undefined'
    end block

    allocate(arr(N))
    call random_number(arr)
    arr = arr * 100.0d0 ! avoid small numbers

    ! --- Test 1: Element-wise Loop (Fortran controls flow) ---
    ! Even with Fast Path, we cross the language boundary N times.
    print *, "1. Element-wise Loop (calling Julia inside loop)..."
    
    ! Get fast pointer to avoid dispatch overhead (giving it the best chance)
    raw_ptr = get_function_pointer("perf_sqrt_scalar", "Float64", "Float64")
    call c_f_procpointer(raw_ptr, c_sqrt)
    
    call cpu_time(t1)
    do i = 1, N
        val = c_sqrt(arr(i))
        ! In a real app, we'd store val, but here we just compute
        arr(i) = val 
    end do
    call cpu_time(t2)
    print "(A, F10.6, A)", "   Time: ", t2 - t1, " s"

    ! Reset array
    call random_number(arr)
    arr = arr * 100.0d0

    ! --- Test 2: Vectorized Batch Call (Julia controls flow) ---
    ! We cross the boundary ONCE. Julia handles the loop/simd.
    print *, "2. Vectorized Batch Call (Zero-Copy + SIMD)..."
    
    call cpu_time(t1)
    ! 1. Wrap (Zero-Cost)
    wrapped_arr = julia_wrap_array(arr)
    ! 2. Call once
    ! Warm-up call (to exclude JIT compilation time)
    res = julia%call("perf_sqrt_vector_bang", wrapped_arr)
    
    call cpu_time(t1)
    res = julia%call("perf_sqrt_vector_bang", wrapped_arr)
    call cpu_time(t2)
    
    print "(A, F10.6, A)", "   Time: ", t2 - t1, " s"

    print *, "--- Conclusion ---"
    print *, "Moving the loop into Julia (Batching) minimizes boundary crossings."
    print *, "However, for simple scalar ops (like sqrt), Fortran's Fast Path loop"
    print *, "is extremely competitive. Batching shines for complex ops or library calls."

end program access_patterns