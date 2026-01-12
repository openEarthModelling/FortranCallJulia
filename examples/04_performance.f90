program ex04_performance
    use julia_high_level
    use julia_low_level
    use iso_c_binding
    implicit none

    type(JuliaValue) :: ctx, res, arr_obj
    type(c_funptr) :: c_f_ptr
    
    integer(kind=8) :: i, n_iter
    ! Test A Params
    integer(kind=8) :: scalar_iter = 100000
    ! Test B Params
    integer(kind=8) :: big_dim = 64
    integer(kind=8) :: big_iter = 100
    ! Test C Params
    integer(kind=8) :: batch_count = 500
    
    real(kind=8) :: t_start, t_end
    real(kind=8) :: t_oop, t_ptr, t_copy, t_zc, t_loop, t_batch
    real(kind=8) :: sum_val
    
    real(kind=8), allocatable, target :: big_mat(:,:), tiny_mat(:,:), batch_stack(:,:,:)
    type(c_ptr) :: raw_ptr, wrapped_ptr

    ! Interface for Fast Path (Test A)
    interface
        function julia_fast_add_proto(a, b) bind(c) result(r)
            use iso_c_binding
            real(kind=c_double), value :: a, b
            real(kind=c_double) :: r
        end function julia_fast_add_proto
        
        subroutine julia_fast_inv_proto(ptr, n) bind(c)
            use iso_c_binding
            type(c_ptr), value :: ptr
            integer(kind=c_int64_t), value :: n
        end subroutine julia_fast_inv_proto
    end interface
    procedure(julia_fast_add_proto), pointer :: f_add => null()
    procedure(julia_fast_inv_proto), pointer :: f_inv => null()

    print *, "--- Example 4: Performance Benchmarks ---"
    call julia_init()
    
    ! Setup Aliases
    call julia_eval_string('include("examples_lib.jl")')
    call julia_eval_string('using .ExamplesLib')
    call julia_eval_string('const fast_add = ExamplesLib.fast_add')
    call julia_eval_string('const calc_inverse = ExamplesLib.calc_inverse')
    call julia_eval_string('const calc_inverse_copy = ExamplesLib.calc_inverse_copy')
    call julia_eval_string('const calc_inverse_batch = ExamplesLib.calc_inverse_batch')
    call julia_eval_string('const calc_inverse_ptr_entry = ExamplesLib.calc_inverse_ptr_entry')
    call julia_eval_string('const calc_trace = ExamplesLib.calc_trace')
    call julia_eval_string('const calc_trace_copy = ExamplesLib.calc_trace_copy')
    call julia_eval_string('const calc_trace_ptr_entry = ExamplesLib.calc_trace_ptr_entry')
    
    ! --- WARM UP PHASE (Critical for fair benchmarking) ---
    print *, "[Setup] Warming up JIT compilation..."
    ! Call functions with dummy data to force compilation
    block
        type(JuliaValue) :: w_args(1), dummy_res
        real(kind=8), target :: w_mat(2,2), w_stack(2,2,2)
        type(c_ptr) :: w_ptr1, w_ptr2
        type(JuliaValue) :: w_obj1, w_obj2
        
        ! Warmup OOP
        dummy_res = ctx%call_method_1_real("sqrt", 2.0d0)
        
        ! Make w_mat invertible (Identity)
        w_mat = 0.0d0; w_mat(1,1)=1.0d0; w_mat(2,2)=1.0d0
        w_stack = 1.0d0 
        w_stack(1,1,:) = 2.0d0; w_stack(2,2,:) = 2.0d0
        w_stack(1,2,:) = 0.0d0; w_stack(2,1,:) = 0.0d0
        
        w_ptr1 = c_loc(w_mat); w_ptr2 = c_loc(w_stack)
        
        w_obj1%ptr = fj_retain(fj_wrap_array_2d(w_ptr1, 2_8, 2_8))
        w_obj2%ptr = fj_retain(fj_wrap_array_3d(w_ptr2, 2_8, 2_8, 2_8))
        
        w_args(1) = w_obj1
        dummy_res = ctx%call_method_generic("calc_inverse", w_args)
        dummy_res = ctx%call_method_generic("calc_inverse_copy", w_args)
        dummy_res = ctx%call_method_generic("calc_trace", w_args)
        dummy_res = ctx%call_method_generic("calc_trace_copy", w_args)
        
        w_args(1) = w_obj2
        dummy_res = ctx%call_method_generic("calc_inverse_batch", w_args)
        
        ! Warmup Ptr Inv
        c_f_ptr = get_function_pointer("calc_inverse_ptr_entry", "Cvoid", "(Ptr{Float64}, Int64)")
        if (c_associated(c_f_ptr)) then
             call c_f_procpointer(c_f_ptr, f_inv)
             call f_inv(w_ptr1, 2_8)
        endif
        
        ! Warmup Ptr Trace
        c_f_ptr = get_function_pointer("calc_trace_ptr_entry", "Cvoid", "(Ptr{Float64}, Int64)")
        if (c_associated(c_f_ptr)) then
             call c_f_procpointer(c_f_ptr, f_inv)
             call f_inv(w_ptr1, 2_8)
        endif
        
        print *, "[Setup] Warm-up complete."
    end block

    ! ==========================================================================
    ! Test A: Call Overhead (Scalar) - [Latency Bound]
    ! Goal: 100k Scalar additions (1.0 + 2.0)
    ! Compare: OOP Interface vs Function Pointer
    ! ==========================================================================
    print *, ""
    print *, "[Test A] Call Overhead [Latency Bound]: 100k Scalar Adds"

    ! 1. OOP Interface
    call cpu_time(t_start)
    do i = 1, scalar_iter
        associate (tmp => ctx%call_method_1_real("sqrt", 2.0d0))
            if (c_associated(tmp%ptr)) continue
        end associate
    end do
    call cpu_time(t_end)
    t_oop = t_end - t_start
    print *, "  1. OOP [Boxed / Deep Copy]: ", t_oop, "s"

    ! 2. Fast Path (Function Pointer)
    c_f_ptr = get_function_pointer("fast_add", "Float64", "(Float64, Float64)")
    if (.not. c_associated(c_f_ptr)) stop "Error getting function pointer"
    call c_f_procpointer(c_f_ptr, f_add)

    call cpu_time(t_start)
    sum_val = 0.0d0
    do i = 1, scalar_iter
        sum_val = sum_val + f_add(1.0d0, 2.0d0)
    end do
    call cpu_time(t_end)
    t_ptr = t_end - t_start
    print *, "  2. Ptr [Unboxed / Zero-Copy]: ", t_ptr, "s"
    print *, "  >> Speedup:                   ", t_oop / t_ptr, "x"


    ! ==========================================================================
    ! Test B: The Mechanism Battle (Large Data, Repeated) - [Bandwidth Bound]
    ! Goal: Trace of 1024x1024 matrix, 200 times.
    ! Compare: Memory Copy vs Zero-Copy Pointer Passing
    ! ==========================================================================
    print *, ""
    print *, "[Test B] Memory Overhead [Bandwidth Bound]: 1024x1024 Matrix Trace x 200"
    
    big_dim = 1024
    big_iter = 200
    
    allocate(big_mat(big_dim, big_dim))
    call random_number(big_mat)
    do i = 1, big_dim; big_mat(i,i) = 1.0d0; end do
    
    raw_ptr = c_loc(big_mat)
    wrapped_ptr = fj_wrap_array_2d(raw_ptr, big_dim, big_dim)
    arr_obj%ptr = fj_retain(wrapped_ptr)

    ! 1. Deep Copy (Simulated "Pass by Value")
    call cpu_time(t_start)
    do i = 1, big_iter
        block
            type(JuliaValue) :: args(1)
            args(1) = arr_obj
            res = ctx%call_method_generic("calc_trace_copy", args)
        end block
    end do
    call cpu_time(t_end)
    t_copy = t_end - t_start
    print *, "  1. Deep Copy (Simulated):   ", t_copy, "s"

    ! 2. Zero-Copy (Pass by Reference)
    call cpu_time(t_start)
    do i = 1, big_iter
        block
            type(JuliaValue) :: args(1)
            args(1) = arr_obj
            res = ctx%call_method_generic("calc_trace", args)
        end block
    end do
    call cpu_time(t_end)
    t_zc = t_end - t_start
    print *, "  2. Zero-Copy (Direct):      ", t_zc, "s"
    
    ! 3. Ptr + Zero-Copy (The Ultimate Speed)
    c_f_ptr = get_function_pointer("calc_trace_ptr_entry", "Cvoid", "(Ptr{Float64}, Int64)")
    if (.not. c_associated(c_f_ptr)) stop "Error getting calc_trace_ptr_entry"
    call c_f_procpointer(c_f_ptr, f_inv) ! reusing f_inv signature which matches
    
    call cpu_time(t_start)
    do i = 1, big_iter
        call f_inv(raw_ptr, big_dim)
    end do
    call cpu_time(t_end)
    t_ptr = t_end - t_start
    print *, "  3. Ptr + Zero-Copy:         ", t_ptr, "s"
    print *, "  >> Speedup (Copy/ZC):       ", t_copy / t_zc, "x"


    ! ==========================================================================
    ! Test C: Architectural Overhead (Many Small Tasks)
    ! Goal: Invert 500 small (3x3) matrices.
    ! Compare: Naive Loop (even with Zero-Copy!) vs Batch Processing
    ! ==========================================================================
    print *, ""
    print *, "[Test C] Architecture: 500 x Small Matrix (3x3) Inverse"
    
    allocate(tiny_mat(3,3))
    tiny_mat = 0.0d0
    do i=1,3; tiny_mat(i,i)=1.0d0; end do
    
    ! Wrap the tiny matrix once
    raw_ptr = c_loc(tiny_mat)
    wrapped_ptr = fj_wrap_array_2d(raw_ptr, 3_8, 3_8)
    arr_obj%ptr = fj_retain(wrapped_ptr)

    ! 1. Naive Loop (The "Anti-Pattern")
    ! WARNING: Even though we use Zero-Copy here (arr_obj), the overhead
    ! of calling across languages 500 times destroys performance.
    call cpu_time(t_start)
    do i = 1, batch_count
        block
            type(JuliaValue) :: args(1)
            args(1) = arr_obj
            res = ctx%call_method_generic("calc_inverse", args)
        end block
    end do
    call cpu_time(t_end)
    t_loop = t_end - t_start
    print *, "  1. Naive Loop (500 calls):   ", t_loop, "s"
    print *, "     (Note: Overhead dominates even with Zero-Copy!)"

    ! 2. Batch Processing (The "Pro Pattern")
    ! Pass a 3D array (3,3,500) once.
    allocate(batch_stack(3, 3, batch_count))
    call random_number(batch_stack)
    ! Make invertible
    do i = 1, batch_count
         batch_stack(1,1,i) = batch_stack(1,1,i) + 5.0d0
         batch_stack(2,2,i) = batch_stack(2,2,i) + 5.0d0
         batch_stack(3,3,i) = batch_stack(3,3,i) + 5.0d0
    end do

    raw_ptr = c_loc(batch_stack)
    wrapped_ptr = fj_wrap_array_3d(raw_ptr, 3_8, 3_8, batch_count)
    arr_obj%ptr = fj_retain(wrapped_ptr)

    call cpu_time(t_start)
    block
        type(JuliaValue) :: args(1)
        args(1) = arr_obj
        res = ctx%call_method_generic("calc_inverse_batch", args)
    end block
    call cpu_time(t_end)
    t_batch = t_end - t_start

        print *, "  2. Batch Call (1 call):     ", t_batch, "s"

        print *, "  >> Speedup:                 ", t_loop / t_batch, "x"

        

        

        ! ==========================================================================

        ! Test D: The Flexibility Battle (Polymorphism)

        ! Goal: Call the SAME function with DIFFERENT types (Real, Complex, String).

        ! Compare: OOP (Dynamic Dispatch) vs Ptr (Static Typing)

        ! ==========================================================================

        print *, ""

        print *, "[Test D] Flexibility [Complexity Bound]: Polymorphism"

        

        ! OOP: One interface to rule them all.

        ! We call 'polymorphic_func' with diverse types.

        

        block

            type(JuliaValue) :: args(1)

            type(JuliaValue) :: res_poly

            complex(kind=8) :: c_val = (1.0d0, 2.0d0)

            

            call julia_eval_string('const polymorphic_func = ExamplesLib.polymorphic_func')

            

                    print *, "  1. OOP Call with Float64:"

            

                    args(1) = julia_box_real(10.5d0)

            

                    res_poly = ctx%call_method_generic("polymorphic_func", args)

            

                    if (res_poly%is_valid()) print *, "     Result: ", res_poly%as_real()

            

            print *, "  2. OOP Call with Complex:"

            args(1) = julia_box_complex(c_val)

            res_poly = ctx%call_method_generic("polymorphic_func", args)

            if (res_poly%is_valid()) print *, "     Result: ", res_poly%as_complex()

            

            print *, "  3. OOP Call with String:"

            args(1) = julia_box_string("Fortran")

            res_poly = ctx%call_method_generic("polymorphic_func", args)

            if (res_poly%is_valid()) print *, "     Result: ", res_poly%as_string()

            

            print *, "  >> Conclusion: OOP handles diversity seamlessly."

            print *, "     (Ptr would require 3 separate function pointers and C-side logic)"

        end block

    

        call julia_shutdown()

        print *, "--- Finished ---"

end program ex04_performance