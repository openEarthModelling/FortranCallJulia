program ex01_quickstart
    use julia_high_level
    implicit none

    type(JuliaValue) :: julia ! Helper object for method dispatch
    type(JuliaValue) :: res
    real(kind=8) :: sum_result

    print *, "--- Example 1: Quickstart (Standard Workflow) ---"

    ! 1. Initialize the Julia Runtime
    call julia_init()

    ! 2. Load your Julia Code
    call julia_include_exe_relative("examples_lib.jl")
    call julia_eval_string('using .ExamplesLib')
    block
        type(JuliaValue) :: chk
        chk = julia_eval('isdefined(Main, :ExamplesLib)')
        if (.not. chk%as_logical()) error stop 'examples_lib.jl did not load: ExamplesLib undefined'
    end block

    ! 3. Call a simple function: greet(name)
    !    Equivalent to Julia: res = ExamplesLib.greet("Fortran User")
    res = julia%call("ExamplesLib.greet", "Fortran User")
    
    ! 4. Call a calculation function: add_numbers(x, y)
    !    Equivalent to Julia: res = ExamplesLib.add_numbers(10.5, 20.0)
    res = julia%call("ExamplesLib.add_numbers", 10.5d0, 20.0d0)
    
    ! Convert the result back to Fortran real (Unboxing)
    sum_result = res%as_real()
    print *, "Result of 10.5 + 20.0 = ", sum_result

    ! 5. Shutdown
    call julia_shutdown()

end program ex01_quickstart
