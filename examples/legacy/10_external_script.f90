program ex10_external_script
    use julia_high_level
    use julia_low_level
    use iso_c_binding
    implicit none

    type(JuliaValue) :: ctx, mat_obj, res_obj
    type(JuliaValue), allocatable :: args(:)
    real(kind=c_double), target :: matrix(2,2)
    type(c_ptr) :: raw_ptr, wrapped_ptr
    real(kind=c_double) :: val = 2.5d0
    integer :: i

    print *, "--- Example 10: Loading External Julia Script (Generic Call) ---"
    call julia_init()

    ! 1. Load the script file
    print *, "Loading 'user_script.jl'..."
    call julia_eval_string('include("user_script.jl")')
    
    ! 2. Import module and alias function to Main for easy C-access
    ! Note: Our C bridge looks in Main or FortranBridge for function names.
    ! "UserLogic.run_simulation" is not a valid function name symbol in Main directly (it's a path).
    ! So we create an alias "RunSim" in Main.
    print *, "Aliasing UserLogic.run_simulation to Main.RunSim..."
    call julia_eval_string('using .UserLogic')
    call julia_eval_string('const RunSim = UserLogic.run_simulation')

    ! 3. Prepare Data (2x2 Matrix)
    ! Fortran is Col-Major: 1,2,3,4 -> [[1,3], [2,4]]
    matrix(1,1) = 1.0d0
    matrix(2,1) = 2.0d0
    matrix(1,2) = 3.0d0
    matrix(2,2) = 4.0d0
    
    print *, "Fortran Matrix:"
    print *, matrix(1, :)
    print *, matrix(2, :)

    raw_ptr = c_loc(matrix)
    wrapped_ptr = fcj_wrap_array_2d(raw_ptr, 2_8, 2_8)
    mat_obj%ptr = fcj_retain(wrapped_ptr)

    ! 4. Call the aliased function using Generic Interface
    print *, "Calling 'RunSim' with scalar:", val
    ! res_obj = ctx%call_method_2_obj_real("RunSim", mat_obj, val)
    
    allocate(args(2))
    args(1) = mat_obj
    args(2) = julia_box_real(val)
    
    res_obj = ctx%call_method_generic("RunSim", args)
    
    ! 5. Display Result
    if (res_obj%is_valid()) then
        print *, "Result received:"
        block
            type(JuliaValue) :: dummy
            dummy = ctx%call_method_1_obj("display", res_obj)
        end block
    else
        print *, "Error: ", get_last_error_message()
    end if

    call julia_shutdown()
    print *, "--- Finished ---"

end program ex10_external_script
