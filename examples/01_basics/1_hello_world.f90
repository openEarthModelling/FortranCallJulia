program ex01_basics
    use julia_high_level
    implicit none

    type(JuliaValue) :: dummy, res
    character(len=:), allocatable :: err_msg

    print *, "--- Example 1: Hello World & Modern API ---"

    ! 1. Initialize
    print *, "[Fortran] Initializing Julia Runtime..."
    call julia_init()

    ! 2. Modern Generic Call (Auto-boxing)
    ! The 'call' method automatically handles:
    ! - Integer -> Int64/Int32
    ! - Real -> Float64
    ! - String -> String
    ! - Complex -> ComplexF64
    ! - Logical -> Bool
    
    print *, "[Fortran] Calling Julia 'sqrt(16.0)'..."
    res = dummy%call("sqrt", 16.0d0)

    if (res%is_valid()) then
        print *, "[Fortran] Result: ", res%as_real()
    else
        print *, "[Fortran] Error calling sqrt."
    endif

    ! 3. Multiple Arguments
    ! Let's define a quick function to call
    call julia_eval_string('greet(name, n) = println("Hello $name, count: $n")')
    
    print *, "[Fortran] Calling 'greet'..."
    ! Pass String and Integer naturally
    res = dummy%call("greet", "User", 42)

    ! 4. Error Handling
    print *, ""
    print *, "[Fortran] Intentional Error Test..."
    res = dummy%call("non_existent_func", 123)

    if (.not. res%is_valid()) then
        err_msg = get_last_error_message()
        print *, "[Fortran] Caught expected error: ", err_msg
    endif

    ! 5. Shutdown
    print *, ""
    print *, "[Fortran] Shutting down..."
    call julia_shutdown()

end program ex01_basics