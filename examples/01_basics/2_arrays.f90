program ex02_arrays
    use julia_high_level
    use julia_low_level
    use iso_c_binding
    implicit none

    type(JuliaValue) :: dummy, res
    type(JuliaValue) :: vec_obj, mat_obj
    
    ! Arrays
    real(kind=8), target :: vec(5)
    real(kind=8), target :: matrix(3,3)
    real(kind=8), target :: hyper(2,3,4,5)   ! 4D: ranks beyond 3 work too
    type(c_ptr) :: raw_ptr, wrapped_ptr
    integer(kind=c_long) :: dims(4)          ! extents in Fortran dim order
    
    ! Variables for primitive call
    integer :: i_val = 10
    logical :: b_val = .true.
    integer :: k

    print *, "--- Example 2: Arrays & Memory Management ---"
    call julia_init()
    
    ! Load Library
    call julia_include_exe_relative("examples_lib.jl")
    call julia_eval_string('using .ExamplesLib')
    block
        type(JuliaValue) :: chk
        chk = julia_eval('isdefined(Main, :ExamplesLib)')
        if (.not. chk%as_logical()) error stop 'examples_lib.jl did not load: ExamplesLib undefined'
    end block
    
    ! Alias functions
    call julia_eval_string('const process_primitives = ExamplesLib.process_primitives')
    call julia_eval_string('const modify_vector! = ExamplesLib.modify_vector!')
    call julia_eval_string('const modify_matrix! = ExamplesLib.modify_matrix!')

    ! ==========================================================================
    ! Part A: Simple Calls (Modern Syntax)
    ! ==========================================================================
    print *, "[Part A] Calling with Primitives (Auto-Boxed)"
    ! Function signature: process_primitives(i, b, s, c)
    res = dummy%call("process_primitives", i_val, b_val, "Hello", (1.0d0, 2.0d0))
    
    if (res%is_valid()) then
        print *, "  Result (Complex): ", res%as_complex()
    endif

    ! ==========================================================================
    ! Part B: Zero-Copy Array Passing
    ! ==========================================================================
    print *, ""
    print *, "[Part B] Zero-Copy Arrays"
    print *, "  Passing large Fortran arrays to Julia without copying data."

    ! --- 1. Vector (1D) ---
    vec = 10.0d0
    print *, "  1. Vector before: ", vec(1)
    
    ! Step 1: Wrap the raw Fortran pointer. The C-level API is rank-generic:
    ! pass ndim plus the extents in Fortran dimension order.
    raw_ptr = c_loc(vec)
    dims(1) = 5_c_long
    wrapped_ptr = fcj_wrap_array(raw_ptr, 1_c_long, dims)
    
    ! Step 2: Manage it as a JuliaValue (so GC doesn't kill it prematurely if we stored it)
    vec_obj%ptr = fcj_retain(wrapped_ptr) 
    
    ! Step 3: Call function passing the object
    ! Note: 'vec_obj' is already a Julia Object, so we pass it directly.
    ! The generic 'call' interface accepts Class(*) which includes JuliaValue type!
    res = dummy%call("modify_vector!", vec_obj)
    
    print *, "  1. Vector after:  ", vec(1)
    if (vec(1) == -10.0d0) then
        print *, "     [SUCCESS] Vector modified in place."
    endif

    ! --- 2. Matrix (2D) ---
    matrix = 0.0d0
    
    ! Step 1: Wrap
    raw_ptr = c_loc(matrix)
    dims(1:2) = [3_c_long, 3_c_long]
    wrapped_ptr = fcj_wrap_array(raw_ptr, 2_c_long, dims)
    mat_obj%ptr = fcj_retain(wrapped_ptr)

    ! Step 2: Call
    res = dummy%call("modify_matrix!", mat_obj)

    print *, "  2. Matrix(1,1) after:  ", matrix(1,1)
    if (matrix(1,1) == 100.0d0) then
        print *, "     [SUCCESS] Matrix modified in place."
    endif

    ! --- 3. Hypermatrix (4D, zero-copy through the rank-generic API) ---
    ! The high-level SDK form is simply  vec_obj = julia_wrap_array(hyper)
    ! (extents derived from size()); here we exercise the raw C form and
    ! verify the wrap via introspection.
    hyper = 0.0d0
    raw_ptr = c_loc(hyper)
    dims(1:4) = [2_c_long, 3_c_long, 4_c_long, 5_c_long]
    wrapped_ptr = fcj_wrap_array(raw_ptr, 4_c_long, dims)
    mat_obj%ptr = fcj_retain(wrapped_ptr)
    print *, "  3. Rank-4 wrap: ndims=", mat_obj%ndims(), &
             " sizes=", (mat_obj%size_dim(k), k=1,4)
    if (mat_obj%ndims() == 4 .and. mat_obj%size_dim(4) == 5) then
        print *, "     [SUCCESS] 4D array wrapped zero-copy (ndims=4)."
    endif
    
    call julia_shutdown()

end program ex02_arrays
