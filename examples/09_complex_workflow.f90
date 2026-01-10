program ex09_complex_workflow
    use julia_high_level
    use julia_low_level
    use iso_c_binding
    implicit none

    type(JuliaValue) :: ctx
    type(JuliaValue) :: mat_obj, res_obj
    real(kind=c_double), target :: matrix(3,3)
    type(c_ptr) :: raw_ptr, wrapped_ptr
    integer :: i
    real(kind=c_double) :: x_val

    print *, "--- Example 9: Complex Workflow (LinAlg + SpecialFuncs) ---"
    call julia_init()

    ! 1. Initialize Matrix A (Diagonal 2.0)
    matrix = 0.0d0
    do i = 1, 3
        matrix(i, i) = 2.0d0
    end do
    
    ! 2. Wrap Matrix
    raw_ptr = c_loc(matrix)
    wrapped_ptr = fj_wrap_array_2d(raw_ptr, 3_8, 3_8)
    mat_obj%ptr = fj_retain(wrapped_ptr)
    
    ! 3. Define Scalar x
    x_val = 5.0d0
    
    print *, "Calling 'complex_demo_func' with Matrix (3x3) and x =", x_val
    print *, "Logic: B = J0(x)*A + inv(A); Return eigen(B).values"
    
    ! 4. Call Function (Method 2: Obj + Real)
    res_obj = ctx%call_method_2_obj_real("complex_demo_func", mat_obj, x_val)
    
    ! 5. Display Result
    if (res_obj%is_valid()) then
        print *, "Result received from Julia."
        block
            type(JuliaValue) :: dummy
            dummy = ctx%call_method_1_obj("display", res_obj)
        end block
    else
        print *, "Error calling function: ", get_last_error_message()
    end if

    call julia_shutdown()
    print *, "--- Finished ---"

end program ex09_complex_workflow
