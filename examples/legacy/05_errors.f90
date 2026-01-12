program ex05_errors
    use julia_high_level
    implicit none

    type(JuliaValue) :: ctx, res
    character(len=:), allocatable :: msg

    print *, "--- Example 5: Error Handling ---"
    call julia_init()

    print *, "Attempting to call a non-existent function..."
    
    ! This should fail safely and set the error state
    res = ctx%call_method_1_real("this_function_does_not_exist", 1.0d0)
    
    if (.not. res%is_valid()) then
        print *, "Call failed as expected."
        
        msg = get_last_error_message()
        print *, "Error Message from Bridge: "
        print *, "  >> ", msg
    else
        print *, "Unexpected success?"
    end if

    print *, "Attempting valid call..."
    res = ctx%call_method_1_real("sqrt", 4.0d0)
    if (res%is_valid()) then
        print *, "Recovered and called valid function successfully."
    endif

    call julia_shutdown()
    print *, "--- Finished ---"

end program ex05_errors
