program ex03_performance
    use julia_high_level
    use iso_c_binding
    implicit none

    type(JuliaValue) :: ctx
    type(JuliaValue) :: res
    type(c_funptr) :: c_f_ptr
    real(kind=c_double) :: start_time, end_time, delta_oop, delta_fast
    integer :: i, n_iter
    real(kind=c_double) :: sum_val
    
    ! Interface for the function pointer
    abstract interface
        function julia_add_proto(a, b) bind(c) result(r)
            use iso_c_binding
            real(kind=c_double), value :: a, b
            real(kind=c_double) :: r
        end function julia_add_proto
    end interface
    procedure(julia_add_proto), pointer :: f_add => null()

    n_iter = 100000
    print *, "--- Example 3: Performance (Fast Path vs OOP) ---"
    print *, "Iterations: ", n_iter
    
    call julia_init()

    ! 1. OOP Call (Overhead expected)
    ! We can't easily measure pure add overhead because we don't have a simple 'add' wrapper in our limited SDK yet.
    ! But we can call 'sqrt'.
    
    print *, "Benchmarking OOP calls (sqrt)..."
    call cpu_time(start_time)
    do i = 1, n_iter
        res = ctx%call_method_1_real("sqrt", 2.0d0)
        ! Destructor is called automatically when res is reassigned? 
        ! Fortran Finalization rules are tricky on assignment. 
        ! Ideally we should explicitly destroy or use a block.
        ! But for this simple bench, let's just loop.
    end do
    call cpu_time(end_time)
    delta_oop = end_time - start_time
    print *, "OOP Time: ", delta_oop, " seconds"

    ! 2. Fast Path (Function Pointer)
    print *, "Benchmarking Fast Path (julia_add)..."
    
    ! Register/Get Pointer
    ! "julia_add" is defined in middleware.jl
    c_f_ptr = get_function_pointer("julia_add", "Float64", "(Float64, Float64)")
    
    if (.not. c_associated(c_f_ptr)) then
        print *, "Error: Could not get function pointer."
        call julia_shutdown()
        stop
    end if
    
    call c_f_procpointer(c_f_ptr, f_add)
    
    call cpu_time(start_time)
    sum_val = 0.0d0
    do i = 1, n_iter
        sum_val = sum_val + f_add(1.0d0, 2.0d0)
    end do
    call cpu_time(end_time)
    delta_fast = end_time - start_time
    
    print *, "Fast Path Time: ", delta_fast, " seconds"
    print *, "Speedup: ", delta_oop / delta_fast, "x"

    call julia_shutdown()
    print *, "--- Finished ---"

end program ex03_performance
