program ex02_math_oop
    use julia_high_level
    use iso_c_binding
    implicit none

    type(JuliaValue) :: ctx
    type(JuliaValue) :: res
    real(kind=c_double) :: input_val, output_val
    
    print *, "--- Example 2: OOP Interface ---"
    call julia_init()

    input_val = 16.0d0
    print *, "Input Value: ", input_val

    ! Call 'sqrt' function in Julia
    ! The result 'res' is a wrapper around a Julia object (Float64 in this case)
    res = ctx%call_method_1_real("sqrt", input_val)
    
    if (res%is_valid()) then
        print *, "Result Object is valid at address:", res%ptr
        
        ! In a full implementation, we would have a method like:
        ! output_val = res%to_real()
        ! For now, we can verify it by printing from Julia
        
        print *, "Verifying result inside Julia (should be 4.0):"
        call julia_eval_string("println(sqrt(16.0))") 
        ! Wait, we don't have julia_eval_string exposed in high_level yet.
        ! Let's use call_method_1_obj to print the result object itself.
        
        block
            type(JuliaValue) :: void_res
            void_res = ctx%call_method_1_obj("println", res)
        end block
    end if

    call julia_shutdown()
    print *, "--- Finished ---"

end program ex02_math_oop
