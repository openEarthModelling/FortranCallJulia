program ex09_kwargs
    use julia_high_level
    use iso_c_binding
    implicit none

    type(JuliaValue) :: ctx
    type(JuliaValue) :: args(2), res
    type(JuliaKwargs) :: opts
    
    print *, "--- Example 9: Keyword Arguments ---"
    call julia_init()

    print *, "Defining Julia function 'greet'..."
    call julia_eval_string('println("Current Module: ", @__MODULE__)')
    
    call julia_eval_string('function greet(name; greeting="Hello", times=1); ' // &
                           'return string(greeting, ", ", name, "! ") ^ times; end')
    
    call julia_eval_string('println("DEBUG: isdefined(Main, :greet) = ", isdefined(Main, :greet))')
    
    call julia_eval_string('println("DEBUG: isdefined(Main, :greet) = ", isdefined(Main, :greet))')
    call julia_eval_string('println("DEBUG: names(Main) = ", names(Main))')

    ! 2. Call with defaults (No kwargs)
    print *, "Calling with default kwargs..."
    block
        args(1) = julia_box_string("Fortran")
        ! Need to pass empty JuliaKwargs, or overload generic.
        ! call_method_generic handles no-kwargs.
        res = ctx%call_method_generic("greet", args(1:1))
    end block
    
    if (res%is_valid()) then
        print *, "Result 1: ", res%as_string()
    else
        print *, "Error calling greet (default): ", get_last_error_message()
    end if

    ! 3. Call with kwargs
    print *, "Calling with kwargs (greeting=""Hi"", times=3)..."
    
    ! Setup Kwargs
    call opts%add("greeting", julia_box_string("Hi"))
    call opts%add("times", julia_box_integer(3_8))
    
    ! Setup Args
    args(1) = julia_box_string("Developer")
    
    res = ctx%call_with_kwargs("greet", args(1:1), opts)
    
    if (res%is_valid()) then
        print *, "Result 2: ", res%as_string()
        if (res%as_string() == "Hi, Developer! Hi, Developer! Hi, Developer! ") then
            print *, "SUCCESS: Kwargs passed correctly."
        else
            print *, "FAILURE: Result mismatch."
        end if
    else
        print *, "Error calling greet (kwargs): ", get_last_error_message()
    end if

    call julia_shutdown()
    print *, "--- Finished ---"

end program ex09_kwargs
