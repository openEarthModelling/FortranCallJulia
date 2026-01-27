program ex_inter_math_operations
    use julia_high_level
    use iso_c_binding
    implicit none

    type(JuliaValue) :: dummy, mat_obj, res_obj, tmp_val
    real(kind=8), target :: matrix(3,3)
    type(c_ptr) :: raw_ptr
    integer :: i, j
    real(kind=8) :: val

    print *, "--- Intermediate Example 1: Math Operations (Linear Algebra) ---"
    
    call julia_init()

    ! 1. Load the Helper Library (Standard Payload)
    print *, "[Fortran] Loading 'examples_lib.jl'..."
    call julia_eval_string('include("examples_lib.jl")')
    call julia_eval_string('using .ExamplesLib')

    ! 2. Prepare Data in Fortran
    ! Let's create a symmetric positive definite matrix
    ! M = [ 2 -1  0 ]
    !     [ -1 2 -1 ]
    !     [ 0 -1  2 ]
    matrix = 0.0d0
    do i = 1, 3
        matrix(i, i) = 2.0d0
        if (i < 3) matrix(i, i+1) = -1.0d0
        if (i > 1) matrix(i, i-1) = -1.0d0
    end do

    print *, "[Fortran] Input Matrix:"
    do i = 1, 3
        print *, matrix(i, :)
    end do

    ! 3. Pass Matrix to Julia (Zero-Copy)
    ! We create a view of the Fortran array.
    ! We use generic 'julia_wrap_array' and pass dimensions explicitly (as int64)
    mat_obj = julia_wrap_array(matrix, 3_8, 3_8)

    ! 4. Compute Inverse in Julia
    ! Call: ExamplesLib.calc_inverse(mat_obj)
    print *, ""
    print *, "[Julia] Computing Inverse..."
    ! We use a dummy dispatcher for the call
    res_obj = dummy%call("ExamplesLib.calc_inverse", mat_obj)
    
    ! 5. Retrieve Result
    ! We can convert the result back to a Fortran array or print elements.
    ! For simplicity here, let's just inspect the result object directly using 'at'.
    ! A Matrix in Julia can be indexed as at_2d(i, j).
    
    print *, "[Fortran] Result Matrix (Inverse):"
    do i = 1, 3
        do j = 1, 3
            ! Using generic 'at' which dispatches to 2D indexing for arrays
            ! It returns a JuliaValue, so we must unbox it using as_real()
            tmp_val = res_obj%at(int(i,8), int(j,8))
            val = tmp_val%as_real()
            write(*, '(F10.4)', advance='no') val
        end do
        print *, ""
    end do
    
    ! 6. Compute Eigenvalues
    ! Call: ExamplesLib.calc_eigenvalues(mat_obj)
    print *, ""
    print *, "[Julia] Computing Eigenvalues..."
    res_obj = dummy%call("ExamplesLib.calc_eigenvalues", mat_obj)
    
    print *, "[Fortran] Eigenvalues:"
    ! The result is a 1D Vector
    do i = 1, 3
        tmp_val = res_obj%at(int(i,8))
        val = tmp_val%as_real()
        print *, "  Eigenvalue ", i, ": ", val
    end do

    call julia_shutdown()

end program ex_inter_math_operations