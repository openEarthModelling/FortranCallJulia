program ex08_special_functions
    use julia_high_level
    use iso_c_binding
    implicit none

    type(JuliaValue) :: ctx
    type(JuliaValue) :: res
    real(kind=c_double) :: nu, x
    
    print *, "--- Example 8: Special Functions (BesselJ) ---"
    call julia_init()

    ! Ensure package is loaded
    print *, "Checking/Installing SpecialFunctions.jl..."
    block
        type(JuliaValue) :: dummy
        dummy = ctx%call_method_0("ensure_special_functions")
    end block

    nu = 0.0d0
    x = 10.0d0
    
    print *, "Calculating BesselJ(0, 10.0)..."
    
    ! We need a call_method_2_real or similar, but our SDK is limited to 1 arg currently in high level.
    ! Workaround: Use eval string for complex calls or extend SDK.
    ! Or better: Register a specific wrapper that takes 1 arg (struct?) or just use eval string which is flexible.
    
    ! Let's use eval_string with formatted string for simplicity in this tutorial,
    ! OR extend the SDK. Extending SDK is better for "completeness".
    ! But for now, let's use the low-level eval string to demonstrate flexibility.
    
    call julia_eval_string('println("Result from Julia: ", Main.FortranBridge.calc_bessel_j(0.0, 10.0))')
    
    ! Let's also try to get the value back using a simpler 1-arg wrapper if we had one.
    ! Since we don't, we will stick to the print above.
    
    call julia_shutdown()
    print *, "--- Finished ---"

end program ex08_special_functions
