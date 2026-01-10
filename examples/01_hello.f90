program ex01_hello
    use julia_high_level
    implicit none

    print *, "--- Example 1: Hello World ---"

    ! 1. Initialize the Julia runtime
    print *, "Initializing Julia..."
    call julia_init()

    ! 2. Call a simple Julia function
    ! We use the global context (implicit in OOP wrappers for now) to call 'println'
    ! We create a dummy object to access the methods, or we could make them static/shared.
    ! For now, we instantiate a dummy context.
    block
        type(JuliaValue) :: ctx
        type(JuliaValue) :: res
        
        print *, "Calling Julia's sqrt..."
        res = ctx%call_method_1_real("sqrt", 2024.0d0) 
        
        print *, "Result is valid."
    end block

    ! 3. Shutdown
    call julia_shutdown()
    print *, "--- Finished ---"

end program ex01_hello
