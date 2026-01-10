program main
    use iso_c_binding
    use julia_high_level
    use julia_low_level
    implicit none

    type(JuliaValue) :: jl_ctx ! Context object for OOP calls
    type(JuliaValue) :: res
    real(kind=c_double) :: val
    integer :: i
    
    ! Variables for Fast Path
    abstract interface
        function julia_add_proto(a, b) bind(c) result(r)
            use iso_c_binding
            real(kind=c_double), value :: a, b
            real(kind=c_double) :: r
        end function julia_add_proto
    end interface
    procedure(julia_add_proto), pointer :: f_add => null()
    type(c_funptr) :: c_f_ptr

    print *, "--- Starting Fortran-Julia Middleware Test ---"

    ! 1. Initialization
    print *, "[Step 1] Initializing Julia..."
    call julia_init()

    ! 2. High-Level OOP Call
    print *, "[Step 2] High-Level OOP Call: sqrt(2.0)"
    
    ! We use jl_ctx to invoke the methods. 
    ! In a full framework, jl_ctx might represent the 'Main' module.
    
    ! Let's call a function that prints inside Julia to see effect
    res = jl_ctx%call_method_1_real("println", 2.0d0) 
    
    ! Let's call sqrt
    res = jl_ctx%call_method_1_real("sqrt", 2.0d0)
    print *, "Called sqrt(2.0). Result object held at address:", res%ptr
    
    ! 3. Low-Level Fast Path
    print *, "[Step 3] Low-Level Fast Path: Registering and Calling julia_add"
    
    ! Get function pointer (this triggers register_f2 in C/Julia)
    c_f_ptr = fj_get_function_pointer(to_c_string("julia_add"))
    
    if (c_associated(c_f_ptr)) then
        call c_f_procpointer(c_f_ptr, f_add)
        print *, "Function pointer obtained."
        
        val = f_add(10.0d0, 20.0d0)
        print *, "Fast Path Result (10+20): ", val
        
        if (abs(val - 30.0d0) < 1.0d-5) then
            print *, "SUCCESS: Fast Path Calculation Correct."
        else
            print *, "FAILURE: Fast Path Calculation Incorrect."
        end if
    else
        print *, "FAILURE: Could not get function pointer."
    end if

    ! 4. Array Passing (Zero-Copy)
    ! We will create a local array, wrap it, and pass it to a Julia function.
    block
        real(kind=c_double), target :: my_array(5) = [1.0d0, 2.0d0, 3.0d0, 4.0d0, 5.0d0]
        type(c_ptr) :: wrapped_array
        type(c_ptr) :: raw_data_ptr
        
        print *, "[Step 4] Zero-Copy Array Passing"
        
        raw_data_ptr = c_loc(my_array)
        wrapped_array = fj_wrap_array_1d(raw_data_ptr, 5_8) ! 5 as int64
        
        print *, "Array wrapped successfully (Address): ", wrapped_array
        
        block
             type(JuliaValue) :: arr_obj
             type(JuliaValue) :: void_res
             
             ! Manually construct the wrapper object
             ! (In a real SDK, we'd have a constructor like: arr_obj = new_julia_array(ptr))
             ! But here we just assign the ptr. Note: fj_wrap_array returns a jl_value_t*.
             ! We should technically RETAIN it if we want it to live long, but for this call it's fine.
             ! However, JuliaValue destructor will try to release it. 
             ! If we didn't retain it, release might fail or be bad.
             ! fj_wrap_array returns a pointer that IS valid.
             ! Let's retain it properly.
             
             arr_obj%ptr = fj_retain(wrapped_array)
             
             print *, "[Step 4.1] Calling Julia: print_array_info(arr)"
             void_res = jl_ctx%call_method_1_obj("print_array_info", arr_obj)
        end block
        
    end block

    print *, "[Step 5] Shutting down..."
    call julia_shutdown()
    print *, "--- Test Finished ---"

end program main
