program ex04_arrays
    use julia_high_level
    use julia_low_level ! For fcj_wrap_array
    use iso_c_binding
    implicit none

    type(JuliaValue) :: ctx, arr_obj
    real(kind=c_double), target :: data(5)
    type(c_ptr) :: raw_ptr, wrapped_ptr
    integer(kind=c_long) :: dims(1)
    integer :: i

    print *, "--- Example 4: Zero-Copy Arrays ---"
    call julia_init()

    ! Initialize Fortran Array
    data = [10.0d0, 20.0d0, 30.0d0, 40.0d0, 50.0d0]
    print *, "Fortran Data (Original): ", data

    ! Wrap it
    raw_ptr = c_loc(data)
    ! Note: the SDK-level form `arr_obj = julia_wrap_array(data)` wraps in one
    ! step; this legacy example keeps the explicit low-level bridge + retain
    ! pattern.

    dims(1) = 5_c_long
    wrapped_ptr = fcj_wrap_array(raw_ptr, 1_c_long, dims)
    arr_obj%ptr = fcj_retain(wrapped_ptr) ! Retain it so we can manage it as an object
    
    ! Pass to Julia to print info
    print *, "Passing to Julia to print info:"
    block
        type(JuliaValue) :: dummy
        dummy = ctx%call_method_1_obj("print_array_info", arr_obj)
    end block

    ! Modify in Julia?
    ! We don't have a 'modify_array' function in middleware.jl yet.
    ! But since it's zero copy, if we had one, it would work.
    ! For now, we trust the 'print_array_info' output shows it received the data correctly.

    call julia_shutdown()
    print *, "--- Finished ---"

end program ex04_arrays
