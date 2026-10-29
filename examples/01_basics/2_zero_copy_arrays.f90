program ex02_zero_copy_arrays
    use julia_high_level
    use iso_c_binding
    implicit none

    ! This example demonstrates the most powerful feature of FortranCallJulia:
    ! Zero-Copy Array Sharing.

    type(JuliaValue) :: julia, dummy, res
    real(kind=8), target :: simulation_grid(100, 100)
    integer :: i, j

    print *, "--- Example 2: Zero-Copy Array Sharing ---"
    call julia_init()
    
    call julia_include_exe_relative("examples_lib.jl")
    call julia_eval_string('using .ExamplesLib')
    block
        type(JuliaValue) :: chk
        chk = julia_eval('isdefined(Main, :ExamplesLib)')
        if (.not. chk%as_logical()) error stop 'examples_lib.jl did not load: ExamplesLib undefined'
    end block

    ! 1. Initialize Fortran Array
    simulation_grid = 0.0d0
    print *, "Initial Grid(1,1): ", simulation_grid(1,1)

    ! 2. Box the Fortran Array into a Julia Object
    !    This creates a Julia Array header pointing to the EXISTING Fortran memory.
    !    NO DATA COPY happens here. Extents are derived from size() by the SDK.
    dummy = julia_wrap_array(simulation_grid)
    
    ! 3. Call Julia Function with the Array
    !    Julia sees a standard Matrix{Float64}.
    !    Any changes Julia makes are written directly to 'simulation_grid'.
    !    ExamplesLib.update_simulation_state!(grid, dt)
    res = julia%call("ExamplesLib.update_simulation_state!", dummy, 0.5d0)
    
    ! 4. Verify Changes in Fortran
    print *, "After Julia Update:"
    print *, "Grid(1,1) [Expected > 0]: ", simulation_grid(1,1)
    print *, "Grid(50,50):              ", simulation_grid(50,50)

    ! Proof of Zero-Copy:
    ! If a copy occurred, 'simulation_grid' would still be 0.0.

    call julia_shutdown()

end program ex02_zero_copy_arrays
