program ex06_multithreading
    use julia_high_level
    use julia_low_level
    use iso_c_binding
    implicit none

    type(JuliaValue) :: ctx, arr_obj, res
    real(kind=8), allocatable, target :: batch_stack(:,:,:)
    type(c_ptr) :: raw_ptr, wrapped_ptr
    integer(kind=8) :: n, m, k
    real(kind=8) :: t1, t2

    print *, "--- Example 6: HPC Multithreading (Parallel Batching) ---"
    
    call julia_init()
    call julia_eval_string('include("examples_lib.jl")')
    call julia_eval_string('using .ExamplesLib')
    call julia_eval_string('const calc_inverse_batch_parallel = ExamplesLib.calc_inverse_batch_parallel')

    call julia_eval_string('println("[Julia] Active Threads: ", Threads.nthreads())')

    ! Prepare Data: 100,000 matrices of size 10x10
    ! Total elements: 100 * 100,000 = 10 Million doubles (80MB)
    ! Inverse is O(N^3), so 10^3 * 100,000 ops.
    n = 10; m = 10; k = 100000
    print *, "[Fortran] Preparing Batch: ", k, "matrices of size", n, "x", m

    allocate(batch_stack(n, m, k))
    call random_number(batch_stack)
    ! Make invertible
    batch_stack(1,1,:) = batch_stack(1,1,:) + 10.0d0

    raw_ptr = c_loc(batch_stack)
    wrapped_ptr = fj_wrap_array_3d(raw_ptr, n, m, k)
    arr_obj%ptr = fj_retain(wrapped_ptr)

    print *, "[Fortran] Calling parallel_batch_inverse..."
    
    call cpu_time(t1)
    block
        type(JuliaValue) :: args(1)
        args(1) = arr_obj
        res = ctx%call_method_generic("calc_inverse_batch_parallel", args)
    end block
    call cpu_time(t2)

    if (res%is_valid()) then
        print *, "Success!"
        print *, "Time:   ", t2 - t1, "s"
        print *, "Throughput: ", real(k)/(t2-t1), " matrices/sec"
    else
        print *, "Error: ", get_last_error_message()
    endif

    call julia_shutdown()

end program ex06_multithreading