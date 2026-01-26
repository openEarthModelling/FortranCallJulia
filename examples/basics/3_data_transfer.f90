program ex02_data_types
    use julia_high_level
    use julia_low_level
    use iso_c_binding
    implicit none

    type(JuliaValue) :: dummy, res
    type(JuliaValue) :: args(4)
    type(JuliaValue) :: vec_obj, mat_obj, arr3d_obj
    
    ! Primitives
    integer(kind=8) :: i_in = 10
    logical :: b_in = .true.
    character(len=20) :: s_in = "Hello"
    complex(kind=8) :: c_in = (1.0d0, 2.0d0)
    complex(kind=8) :: c_out

    ! Arrays
    real(kind=8), target :: vec(5)
    real(kind=8), target :: matrix(3,3)
    real(kind=8), target :: arr3d(2,2,2)
    type(c_ptr) :: raw_ptr, wrapped_ptr
    integer :: k

    print *, "--- Example 2: Data Types & Zero-Copy ---"
    call julia_init()
    
    ! Load Library
    call julia_eval_string('include("examples_lib.jl")')
    call julia_eval_string('using .ExamplesLib')
    
    ! Alias functions to Main for C-Bridge access
    call julia_eval_string('const process_primitives = ExamplesLib.process_primitives')
    call julia_eval_string('const modify_vector! = ExamplesLib.modify_vector!')
    call julia_eval_string('const modify_matrix! = ExamplesLib.modify_matrix!')
    call julia_eval_string('const inspect_3d_array = ExamplesLib.inspect_3d_array')

    ! ==========================================================================
    ! Part A: Primitive Types
    ! ==========================================================================
    print *, "[Part A] Primitives"
    print *, "  Sending: Int=10, Bool=T, Str='Hello', Cmplx=(1,2)"
    
    args(1) = julia_box_integer(i_in)
    args(2) = julia_box_logical(b_in)
    args(3) = julia_box_string(s_in)
    args(4) = julia_box_complex(c_in)
    
    ! Call: process_primitives(i, b, s, c) -> c + i + len(s)
    ! Result should be (1+10+5, 2) = (16.0, 2.0)
    res = dummy%call_method_generic("process_primitives", args)
    
    if (res%is_valid()) then
        c_out = res%as_complex()
        print *, "  Received Complex: ", c_out
        if (real(c_out) == 16.0d0) then
            print *, "  [SUCCESS] Primitives verification passed."
        else
            print *, "  [FAILURE] Logic mismatch."
        endif
    else
        print *, "  [ERROR] Call failed: ", get_last_error_message()
    endif

    ! ==========================================================================
    ! Part B: Arrays (Zero-Copy)
    ! ==========================================================================
    print *, ""
    print *, "[Part B] Zero-Copy Arrays"

    ! --- 1. Vector (1D) ---
    vec = 10.0d0
    print *, "  1. Vector before: ", vec(1)
    
    ! Wrap
    raw_ptr = c_loc(vec)
    wrapped_ptr = fj_wrap_array_1d(raw_ptr, 5_8)
    vec_obj%ptr = fj_retain(wrapped_ptr) ! Retain to manage as object
    
    ! Call modify_vector!(v) -> v[1] *= -1
    block
        type(JuliaValue) :: v_args(1)
        v_args(1) = vec_obj
        res = dummy%call_method_generic("modify_vector!", v_args)
    end block
    
    print *, "  1. Vector after:  ", vec(1)
    if (vec(1) == -10.0d0) then
        print *, "     [SUCCESS] Vector modified in place."
    else
        print *, "     [FAILURE] Vector NOT modified."
    endif

    ! --- 2. Matrix (2D) ---
    matrix = 0.0d0
    print *, "  2. Matrix(1,1) before: ", matrix(1,1)
    
    ! Wrap
    raw_ptr = c_loc(matrix)
    wrapped_ptr = fj_wrap_array_2d(raw_ptr, 3_8, 3_8)
    mat_obj%ptr = fj_retain(wrapped_ptr)
    
    ! Call modify_matrix!(m) -> diagonal += 100
    block
        type(JuliaValue) :: m_args(1)
        m_args(1) = mat_obj
        res = dummy%call_method_generic("modify_matrix!", m_args)
    end block
    
    print *, "  2. Matrix(1,1) after:  ", matrix(1,1)
    if (matrix(1,1) == 100.0d0) then
        print *, "     [SUCCESS] Matrix modified in place."
    else
        print *, "     [FAILURE] Matrix NOT modified."
    endif
    
    ! --- 3. 3D Array ---
    arr3d = 99.0d0
    print *, "  3. 3D Array passing..."
    raw_ptr = c_loc(arr3d)
    wrapped_ptr = fj_wrap_array_3d(raw_ptr, 2_8, 2_8, 2_8)
    arr3d_obj%ptr = fj_retain(wrapped_ptr)
    
    block
        type(JuliaValue) :: a3_args(1)
        a3_args(1) = arr3d_obj
        res = dummy%call_method_generic("inspect_3d_array", a3_args)
    end block
    
    if (res%is_valid()) then
        print *, "     Received back: ", res%as_real()
        if (res%as_real() == 99.0d0) then
             print *, "     [SUCCESS] 3D Array read correctly."
        endif
    endif

    call julia_shutdown()
    print *, "--- Finished ---"

end program ex02_data_types
