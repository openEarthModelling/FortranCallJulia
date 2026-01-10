program test_aot
    use julia_high_level
    use iso_c_binding
    implicit none

    type(JuliaValue) :: dummy, res
    character(len=256) :: path
    integer :: arg_len

    print *, "--- Starting Fortran-Julia AOT Test ---"

    if (command_argument_count() > 0) then
        call get_command_argument(1, path, arg_len)
        path = path(1:arg_len)
        print *, "Initializing Julia with Sysimage: ", trim(path)
        call julia_init_with_image(trim(path))
    else
        print *, "Initializing Julia (Standard Mode)"
        call julia_init()
    endif

    print *, "Calling sqrt(16.0)..."
    res = dummy%call_method_1_real("sqrt", 16.0d0)
    
    if (res%is_valid()) then
        print *, "Success: Result object obtained."
    else
        print *, "Failure: Result object is invalid."
    end if

    print *, "Shutting down..."
    call julia_shutdown()
    
    print *, "Test Complete."
end program test_aot
