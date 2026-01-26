program ex12_benchmark_overhead
    use julia_high_level
    use iso_c_binding
    implicit none

    type(JuliaValue) :: dummy, res
    type(c_funptr) :: raw_func_ptr
    
    ! Interface for the procedure pointer (must match C function signature)
    ! Note: Julia C functions typically take (jl_value_t*, jl_value_t**) etc.
    ! But here we are benchmarking SDK layers.
    ! For a fair "Direct Pointer" comparison, we assume we got a pointer to a C-callable wrapper 
    ! or use the raw C-API call if possible.
    ! In this SDK, `get_function_pointer` returns a C function pointer that we can call directly.
    ! Let's assume we are calling a function `add_one(x::Float64)::Float64`
    
    abstract interface
        function func_signature(x) result(y) bind(c)
            import :: c_double
            real(c_double), value :: x
            real(c_double) :: y
        end function func_signature
    end interface
    
    procedure(func_signature), pointer :: f_ptr => null()

    integer :: i, N
    real(kind=8) :: start_time, end_time, t_legacy, t_modern, t_ptr
    real(kind=8) :: sum_val
    real(kind=8) :: input_val

    N = 100000 ! Number of iterations (reduced for quick turn-around, increase for rigorous testing)
    input_val = 1.0d0

    print *, "--- Example 12: Overhead Benchmark (N =", N, ") ---"
    call julia_init()

    ! Define a simple function: f(x) = x + 1.0
    ! We need a C-callable version for the pointer test.
    ! For now, we will simulate the "Fast Path" using the mechanism in example 04.
    ! But wait, standard Julia functions aren't directly C-callable without @cfunction.
    ! We will just benchmark the dispatch overhead of the TWO methods we have:
    ! 1. Legacy: call_method_1_real
    ! 2. Modern: call(name, val)
    ! 3. (Reference) Pure Fortran
    
    call julia_eval_string("f(x) = x + 1.0")
    
    ! --- 1. Pure Fortran (Baseline) ---
    sum_val = 0.0d0
    call cpu_time(start_time)
    do i = 1, N
        sum_val = sum_val + (input_val + 1.0d0)
    end do
    call cpu_time(end_time)
    print *, "Baseline (Pure Fortran): ", (end_time - start_time), "s"

    ! --- 2. Legacy Interface ---
    sum_val = 0.0d0
    call cpu_time(start_time)
    do i = 1, N
        ! call_method_1_real returns a JuliaValue (new object)
        res = dummy%call_method_1_real("f", input_val)
        ! We must access it to force evaluation/usage
        ! And we MUST free it (handled by assignment/destructor)
        ! Note: Inside the loop, 'res' is overwritten.
    end do
    call cpu_time(end_time)
    t_legacy = end_time - start_time
    print *, "Legacy Interface:        ", t_legacy, "s"

    ! --- 3. Modern Interface ---
    sum_val = 0.0d0
    call cpu_time(start_time)
    do i = 1, N
        ! Generic call with boxing overhead
        res = dummy%call("f", input_val)
    end do
    call cpu_time(end_time)
    t_modern = end_time - start_time
    print *, "Modern Interface:        ", t_modern, "s"
    
    print *, "Overhead Ratio (Modern / Legacy): ", t_modern / t_legacy

    call julia_shutdown()

end program ex12_benchmark_overhead
