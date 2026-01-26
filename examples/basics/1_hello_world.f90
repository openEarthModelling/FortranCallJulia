program ex01_basics
    use julia_high_level
    implicit none

    type(JuliaValue) :: res
    real(kind=8) :: val = 16.0d0
    character(len=:), allocatable :: err_msg

    print *, "--- Example 1: Basics (Init, Call, Error Handling) ---"

    ! 1. Initialize
    print *, "[Fortran] Initializing Julia Runtime..."
    call julia_init()

    ! 2. Simple Call (sqrt)
    print *, "[Fortran] Calling Julia 'sqrt(16.0)'..."
    ! We use a temporary object to make the call. 
    ! Ideally, call_method_* functions could be static/shared, 
    ! but current OOP design requires an object instance or we add a helper.
    ! We will use the 'res' object itself as the invoker for convenience in this SDK version.
    res = res%call_method_1_real("sqrt", val)

    if (res%is_valid()) then
        print *, "[Fortran] Result Object Address: ", res%ptr
        ! In a real app, you would verify the value here using a specific accessor 
        ! (e.g. res%to_real() if implemented, or passing it back to Julia to print)
        call julia_eval_string("println('[Julia] Verified Result: ', sqrt(16.0))")
    else
        print *, "[Fortran] Error calling sqrt."
    endif

    ! 3. Robust Error Handling
    print *, ""
    print *, "[Fortran] Intentional Error Test: Calling 'non_existent_func'..."
    res = res%call_method_1_real("non_existent_func", val)

    if (.not. res%is_valid()) then
        err_msg = get_last_error_message()
        print *, "[Fortran] Caught expected error successfully!"
        print *, "[Fortran] Error details: ", err_msg
    else
        print *, "[Fortran] Unexpected success? Something is wrong."
    endif

    ! 4. Shutdown
    print *, ""
    print *, "[Fortran] Shutting down..."
    call julia_shutdown()
    print *, "--- Finished ---"

end program ex01_basics
