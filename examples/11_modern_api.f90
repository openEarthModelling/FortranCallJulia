program ex11_modern_api
    use julia_high_level
    implicit none

    type(JuliaValue) :: dummy, res
    real(kind=8) :: r_val
    
    print *, "--- Example 11: Modern Generic Call Interface ---"

    ! 1. Initialize
    call julia_init()

    ! 2. Define a simple function in Julia Main scope
    call julia_eval_string("my_doubler(x) = x * 2")
    call julia_eval_string("my_adder(x, y) = x + y")
    call julia_eval_string("my_printer(s) = println(""[Julia] Printing: "", s)")

    ! 3. Generic Call: 1 Argument (Integer)
    print *, "[Fortran] Calling my_doubler(21)..."
    res = dummy%call("my_doubler", 21)
    if (res%is_valid()) then
        print *, "Result (Int): ", res%as_integer()
    else
        print *, "Error calling my_doubler"
    endif

    ! 4. Generic Call: 1 Argument (Real)
    print *, "[Fortran] Calling my_doubler(10.5d0)..."
    res = dummy%call("my_doubler", 10.5d0)
    print *, "Result (Real): ", res%as_real()

    ! 5. Generic Call: 2 Arguments (Real, Real)
    print *, "[Fortran] Calling my_adder(1.1, 2.2)..."
    res = dummy%call("my_adder", 1.1d0, 2.2d0)
    print *, "Result (1.1 + 2.2): ", res%as_real()

    ! 6. Generic Call: String Argument
    print *, "[Fortran] Calling my_printer('Hello from Fortran')..."
    res = dummy%call("my_printer", "Hello from Fortran")
    
    ! 7. Call standard function 'sqrt' (exported by Base)
    print *, "[Fortran] Calling sqrt(16.0)..."
    res = dummy%call("sqrt", 16.0d0)
    print *, "sqrt(16.0) = ", res%as_real()

    call julia_shutdown()
    print *, "--- Finished ---"

end program ex11_modern_api
