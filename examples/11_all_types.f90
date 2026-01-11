program ex11_all_types
    use julia_high_level
    use iso_c_binding
    implicit none

    type(JuliaValue) :: args(4)
    type(JuliaValue) :: res
    type(JuliaValue) :: dummy_res
    type(JuliaValue) :: v_obj, a3_obj
    
    integer(kind=c_int64_t) :: i_val = 42
    logical :: b_val = .true.
    character(len=20) :: s_val = "Hello Fortran"
    complex(kind=c_double) :: c_val = (1.5d0, 2.5d0)
    complex(kind=c_double) :: ret_c
    
    real(kind=c_double), target :: vec(5)
    real(kind=c_double), target :: arr3d(2,2,2)
    integer :: k
    
    print *, "--- Example 11: Full Type Coverage ---"
    call julia_init()
    
    call julia_eval_string('include("types_demo.jl")')
    call julia_eval_string('using .TypesDemo')

    ! --- Test 1: Primitives ---
    print *, "1. Testing Primitives..."
    
    args(1) = julia_box_integer(i_val)
    args(2) = julia_box_logical(b_val)
    args(3) = julia_box_string(s_val)
    args(4) = julia_box_complex(c_val)
    
    res = dummy_res%call_method_generic("process_primitive_types", args)
    
    if (res%is_valid()) then
        ret_c = res%as_complex()
        print *, "Fortran Received Complex Result: ", ret_c
        ! Check logic: c + i + length(s) = (1.5+42+13, 2.5) = (56.5, 2.5)
        if (abs(real(ret_c) - 56.5d0) < 1.0d-5) then
            print *, "SUCCESS: Primitive logic verified."
        else
            print *, "FAILURE: Primitive logic mismatch."
        end if
    else
        print *, "Error calling process_primitive_types: ", get_last_error_message()
    end if

    ! --- Test 2: 1D Vector ---
    print *, "2. Testing 1D Vector..."
    vec = 1.0d0
    v_obj = julia_wrap_array_1d(vec, 5_8)
    
    ! We need to pass v_obj in an array of args
    block
        type(JuliaValue) :: v_args(1)
        v_args(1) = v_obj
        res = dummy_res%call_method_generic("process_vector", v_args)
    end block
    
    print *, "Vector[1] after Julia (Expect 100.0): ", vec(1)
    if (vec(1) == 100.0d0) then
         print *, "SUCCESS: Vector modified in place."
    else
         print *, "FAILURE: Vector not modified."
    end if

    ! --- Test 3: 3D Array ---
    print *, "3. Testing 3D Array..."
    arr3d = 0.0d0
    arr3d(1,1,1) = 7.0d0
    
    a3_obj = julia_wrap_array_3d(arr3d, 2_8, 2_8, 2_8)
    block
        type(JuliaValue) :: a3_args(1)
        a3_args(1) = a3_obj
        res = dummy_res%call_method_generic("process_3d_array", a3_args)
    end block
    
    print *, "Array3D(1,1,1) after Julia (Expect 999.0): ", arr3d(1,1,1)
    if (arr3d(1,1,1) == 999.0d0) then
         print *, "SUCCESS: 3D Array modified in place."
    else
         print *, "FAILURE: 3D Array not modified."
    end if

    call julia_shutdown()
    print *, "--- Finished ---"

end program ex11_all_types
