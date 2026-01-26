program ex03_integration
    use julia_high_level
    use julia_low_level
    use iso_c_binding
    implicit none

    type(JuliaValue) :: dummy, mat_obj, res_obj
    real(kind=8), target :: matrix(3,3)
    type(c_ptr) :: raw_ptr, wrapped_ptr
    integer :: i, j

    print *, "--- Example 3: Integration (Business Logic Baseline) ---"
    call julia_init()

    ! 1. Load Library & Setup Alias
    print *, "[Fortran] Loading 'examples_lib.jl'..."
    call julia_eval_string('include("examples_lib.jl")')
    call julia_eval_string('using .ExamplesLib')
    call julia_eval_string('const calc_inverse = ExamplesLib.calc_inverse')
    call julia_eval_string('const calc_eigenvalues = ExamplesLib.calc_eigenvalues')

    ! 2. Prepare Data (3x3 Matrix)
    ! Identity Matrix + some noise
    matrix = 0.0d0
    do i = 1, 3
        matrix(i, i) = 2.0d0
    end do
    matrix(1, 2) = 1.0d0
    
    print *, "[Fortran] Input Matrix (3x3):"
    do i = 1, 3
        print *, matrix(i, :)
    end do

    ! Wrap (Zero-Copy)
    raw_ptr = c_loc(matrix)
    wrapped_ptr = fj_wrap_array_2d(raw_ptr, 3_8, 3_8)
    mat_obj%ptr = fj_retain(wrapped_ptr)

    ! 3. Call Business Logic: Inverse
    print *, ""
    print *, "[Fortran] Calling 'calc_inverse'..."
    block
        type(JuliaValue) :: args(1)
        args(1) = mat_obj
        res_obj = dummy%call_method_generic("calc_inverse", args)
    end block

    if (res_obj%is_valid()) then
        print *, "[Fortran] Inverse received."
        block
             type(JuliaValue) :: p_args(1), void_res
             p_args(1) = res_obj
             void_res = dummy%call_method_generic("display", p_args)
        end block
    else
        print *, "[Error] Call failed: ", get_last_error_message()
    endif

    ! 4. Call Business Logic: Eigenvalues
    print *, ""
    print *, "[Fortran] Calling 'calc_eigenvalues'..."
    block
        type(JuliaValue) :: args(1)
        args(1) = mat_obj
        res_obj = dummy%call_method_generic("calc_eigenvalues", args)
    end block

    if (res_obj%is_valid()) then
        print *, "[Fortran] Eigenvalues received:"
        block
             type(JuliaValue) :: p_args(1), void_res
             p_args(1) = res_obj
             void_res = dummy%call_method_generic("display", p_args)
        end block
    endif

    call julia_shutdown()
    print *, "--- Finished ---"

end program ex03_integration