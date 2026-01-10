program ex07_linear_algebra
    use julia_high_level
    use julia_low_level
    use iso_c_binding
    implicit none

    type(JuliaValue) :: ctx
    type(JuliaValue) :: mat_obj, inv_res, eigen_res
    real(kind=c_double), target :: matrix(3,3)
    type(c_ptr) :: raw_ptr, wrapped_ptr
    integer :: i, j

    print *, "--- Example 7: Linear Algebra (Matrix Ops) ---"
    call julia_init()

    ! Initialize 3x3 Matrix (Identity + some values)
    ! Fortran is Column-Major. Julia is Column-Major.
    matrix = 0.0d0
    do i = 1, 3
        matrix(i, i) = 2.0d0 ! Diagonal
    end do
    matrix(1, 2) = 1.0d0
    matrix(2, 1) = 1.0d0
    
    print *, "Fortran Matrix:"
    do i = 1, 3
        print *, matrix(i, :)
    end do

    ! Wrap 2D Array
    raw_ptr = c_loc(matrix)
    wrapped_ptr = fj_wrap_array_2d(raw_ptr, 3_8, 3_8)
    mat_obj%ptr = fj_retain(wrapped_ptr)
    
    print *, "Matrix wrapped. Passing to Julia..."
    
    ! Print Info
    block
        type(JuliaValue) :: dummy
        dummy = ctx%call_method_1_obj("print_matrix_info", mat_obj)
    end block

    ! Calculate Inverse
    print *, "Calculating Inverse in Julia..."
    inv_res = ctx%call_method_1_obj("calc_inv", mat_obj)
    
    if (inv_res%is_valid()) then
        print *, "Inverse calculated successfully."
        ! Let's print it using Julia's display
        call julia_eval_string("println('Inverse Matrix:'); display(Main.FortranBridge.FunctionCache[:last_res])") 
        ! Wait, we don't have easy access to the object from eval_string unless we assign it.
        ! Let's use call_method_1_obj("display", inv_res)
        
        block
             type(JuliaValue) :: dummy
             dummy = ctx%call_method_1_obj("display", inv_res)
        end block
    else
        print *, "Error calculating inverse: ", get_last_error_message()
    end if

    ! Calculate Eigenvalues
    print *, "Calculating Eigenvalues..."
    eigen_res = ctx%call_method_1_obj("calc_eigen", mat_obj)
    
    if (eigen_res%is_valid()) then
        print *, "Eigen decomposition done."
        block
             type(JuliaValue) :: dummy
             dummy = ctx%call_method_1_obj("display", eigen_res)
        end block
    end if

    call julia_shutdown()
    print *, "--- Finished ---"

end program ex07_linear_algebra
