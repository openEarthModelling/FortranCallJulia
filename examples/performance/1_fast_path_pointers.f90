program ex04_performance
    use julia_high_level
    use julia_low_level
    use iso_c_binding
    implicit none

    type(JuliaValue) :: ctx, res, arr_obj, copy_obj
    type(c_funptr) :: c_f_ptr
    
    integer(kind=8) :: i
    ! Test A Params
    integer(kind=8) :: scalar_iter = 100000
    ! Test B Params
    integer(kind=8) :: big_dim = 1024
    integer(kind=8) :: big_iter = 200
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
    
    ! --- WARM UP PHASE ---
    print *, "[Setup] Warming up JIT compilation..."
    block
        type(JuliaValue) :: w_args(1), dummy_res
        real(kind=8), target :: w_mat(2,2), w_stack(2,2,2)
        type(c_ptr) :: w_ptr1, w_ptr2
        type(JuliaValue) :: w_obj1, w_obj2
        
        dummy_res = ctx%call_method_1_real("sqrt", 2.0d0)
        w_mat = 0.0d0; w_mat(1,1)=1.0d0; w_mat(2,2)=1.0d0
        w_stack = 1.0d0 
        w_ptr1 = c_loc(w_mat); w_ptr2 = c_loc(w_stack)
        w_obj1 = julia_wrap_array(w_mat, 2_8, 2_8)
        w_obj2 = julia_wrap_array(w_stack, 2_8, 2_8, 2_8)
        w_args(1) = w_obj1
        dummy_res = ctx%call_method_generic("calc_inverse", w_args)
        dummy_res = ctx%call_method_generic("calc_inverse_copy", w_args)
        dummy_res = ctx%call_method_generic("calc_trace", w_args)
        
        w_args(1) = w_obj2
        dummy_res = ctx%call_method_generic("calc_inverse_batch", w_args)
        
        c_f_ptr = get_function_pointer("calc_inverse_ptr_entry", "Cvoid", "(Ptr{Float64}, Int64)")
        if (c_associated(c_f_ptr)) then
             call c_f_procpointer(c_f_ptr, f_inv)
             call f_inv(w_ptr1, 2_8)
        endif
        print *, "[Setup] Warm-up complete."
    end block

    ! ==========================================================================
    ! Test A: Call Overhead (Scalar)
    ! ==========================================================================
    print *, ""
    print *, "[Test A] Call Overhead [Latency Bound]: 100k Scalar Adds"

    call cpu_time(t_start)
    do i = 1, scalar_iter
        res = ctx%call_method_1_real("sqrt", 2.0d0)
    end do
    call cpu_time(t_end)
    t_oop = t_end - t_start
    print *, "  1. OOP [Boxed / Copy]:        ", t_oop, "s"

    c_f_ptr = get_function_pointer("fast_add", "Float64", "(Float64, Float64)")
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
    ! Test B: Memory Overhead (Large Data)
    ! ==========================================================================
    print *, ""
    print *, "[Test B] Memory Overhead [Bandwidth Bound]: 1024x1024 Matrix Trace x 200"
    
    allocate(big_mat(big_dim, big_dim))
    call random_number(big_mat)
    do i = 1, big_dim; big_mat(i,i) = 1.0d0; end do
    raw_ptr = c_loc(big_mat)
    
    ! 1. Deep Copy (Alloc + Memcpy every time)
    call cpu_time(t_start)
    do i = 1, big_iter
        block
            type(JuliaValue) :: args(1)
            copy_obj = julia_copy_array(big_mat) ! <--- NEW: Deep Copy
            args(1) = copy_obj
            res = ctx%call_method_generic("calc_trace", args)
        end block
    end do
    call cpu_time(t_end)
    t_copy = t_end - t_start
    print *, "  1. Deep Copy (Alloc+Memcpy):  ", t_copy, "s"

    ! 2. Zero-Copy (Direct View)
    arr_obj = julia_wrap_array(big_mat, big_dim, big_dim)
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
    print *, "  2. Zero-Copy (Direct View):    ", t_zc, "s"
    
    ! 3. Ptr + Zero-Copy
    c_f_ptr = get_function_pointer("calc_trace_ptr_entry", "Cvoid", "(Ptr{Float64}, Int64)")
    call c_f_procpointer(c_f_ptr, f_inv)
    call cpu_time(t_start)
    do i = 1, big_iter
        call f_inv(raw_ptr, big_dim)
    end do
    call cpu_time(t_end)
    t_ptr = t_end - t_start
    print *, "  3. Ptr + Zero-Copy:            ", t_ptr, "s"
    print *, "  >> Speedup (Copy/ZC):          ", t_copy / t_zc, "x"

    ! ==========================================================================
    ! Test C: Architectural Overhead
    ! ==========================================================================
    print *, ""
    print *, "[Test C] Architecture: 500 x Small Matrix (3x3) Inverse"
    
    allocate(tiny_mat(3,3))
    tiny_mat = 0.0d0; do i=1,3; tiny_mat(i,i)=1.0d0; end do
    arr_obj = julia_wrap_array(tiny_mat, 3_8, 3_8)

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
    print *, "  1. Naive Loop (500 calls):     ", t_loop, "s"

    allocate(batch_stack(3, 3, batch_count))
    call random_number(batch_stack)
    arr_obj = julia_wrap_array(batch_stack, 3_8, 3_8, batch_count)
    call cpu_time(t_start)
    block
        type(JuliaValue) :: args(1)
        args(1) = arr_obj
        res = ctx%call_method_generic("calc_inverse_batch", args)
    end block
    call cpu_time(t_end)
    t_batch = t_end - t_start
    print *, "  2. Batch Call (1 call):       ", t_batch, "s"
    print *, "  >> Speedup:                   ", t_loop / t_batch, "x"

    call julia_shutdown()
    print *, "--- Finished ---"
end program ex04_performance