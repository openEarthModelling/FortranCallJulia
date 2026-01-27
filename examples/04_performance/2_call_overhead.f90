program call_overhead
    use iso_c_binding
    use julia_high_level
    implicit none

    ! --- Variables for Timing ---
    integer, parameter :: N = 100000 ! 100k iterations
    real(8) :: t1, t2
    integer :: i
    real(8) :: x, y
    type(JuliaValue) :: res, julia
    type(c_funptr) :: raw_ptr

    ! --- Fast Path Interface ---
    abstract interface
        function func_add_one(val) bind(c)
            import :: c_double
            real(c_double), value :: val
            real(c_double) :: func_add_one
        end function func_add_one
    end interface
    
    procedure(func_add_one), pointer :: c_func => null()

    print *, "--- Performance Test 1: Call Overhead ---"
    print *, "Iterations:", N

    ! 1. Initialize Julia
    call julia_init()
    ! Load ExamplesLib relative to CWD (build/examples/)
    call julia_eval_string('include("examples_lib.jl")')
    call julia_eval_string('using .ExamplesLib')

    ! 2. Baseline: Pure Fortran
    x = 10.0d0
    call cpu_time(t1)
    do i = 1, N
        y = x + 1.0d0
    end do
    call cpu_time(t2)
    print "(A, F10.6, A)", "1. Pure Fortran:           ", t2 - t1, " s"

    ! 3. Standard Call (The 'Slow' Way)
    ! Note: This includes string lookup, boxing args, unboxing result
    x = 10.0d0
    call cpu_time(t1)
    do i = 1, N
        ! call returns a julia_value, we unbox it
        res = julia%call("perf_add_one", x)
        y = res%as_real()
    end do
    call cpu_time(t2)
    print "(A, F10.6, A)", "2. Standard SDK Call:      ", t2 - t1, " s"

    ! 4. Fast Path (The 'Optimized' Way)
    ! Get a direct C pointer to the compiled Julia function
    raw_ptr = get_function_pointer("perf_add_one", "Float64", "Float64")
    call c_f_procpointer(raw_ptr, c_func)
    
    if (.not. associated(c_func)) then
        print *, "Error: Failed to get function pointer."
        stop
    end if

    x = 10.0d0
    call cpu_time(t1)
    do i = 1, N
        y = c_func(x)
    end do
    call cpu_time(t2)
    print "(A, F10.6, A)", "3. Fast Path Pointer:      ", t2 - t1, " s"

    print *, "--- Conclusion ---"
    print *, "Fast Path eliminates dispatch overhead, bringing Fortran-Julia"
    print *, "calls closer to native C function speeds."

end program call_overhead