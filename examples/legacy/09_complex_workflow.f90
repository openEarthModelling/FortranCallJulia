program ex09_complex_workflow
    use julia_high_level
    use julia_low_level
    use iso_c_binding
    implicit none

    type(JuliaValue) :: ctx
    type(JuliaValue) :: mat_obj, res_obj
    real(kind=c_double), target :: matrix(3,3)
    type(c_ptr) :: raw_ptr, wrapped_ptr
    integer(kind=c_long) :: dims(2)
    integer :: i
    real(kind=c_double) :: x_val

    print *, "--- Example 9: Complex Workflow (Mixed Types) ---"
    call julia_init()

    ! Load Demo Logic
    call julia_eval_string('include("advanced_demo.jl")')
    call julia_eval_string('using .AdvancedDemo')
    call julia_eval_string('const complex_demo_func = AdvancedDemo.complex_demo_func')

    ! 1. Prepare Data
    x_val = 2.5d0
    
    ! 2. Wrap Matrix
    raw_ptr = c_loc(matrix)
    dims(1:2) = [3_c_long, 3_c_long]
    wrapped_ptr = fcj_wrap_array(raw_ptr, 2_c_long, dims)
    mat_obj%ptr = fcj_retain(wrapped_ptr)
    
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
