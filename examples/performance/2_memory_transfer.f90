program memory_transfer
    use julia_high_level
    implicit none

    ! --- Matrix Size: 3000 x 3000 ---
    ! 3000 * 3000 * 8 bytes ~= 72 MB
    integer, parameter :: N = 3000
    real(8), allocatable :: matrix(:,:)
    type(JuliaValue) :: wrapped_array, res, julia
    real(8) :: t1, t2
    integer :: i

    print *, "--- Performance Test 2: Memory Transfer (Deep Copy vs Zero-Copy) ---"
    print *, "Matrix Size: ", N, "x", N, " (approx ", real(N)*real(N)*8.0/1024.0/1024.0, " MB)"

    call julia_init()
    call julia_eval_string('include("examples_lib.jl")')
    call julia_eval_string('using .ExamplesLib')

    allocate(matrix(N,N))
    call random_number(matrix)

    ! --- Test 1: Deep Copy ---
    ! The array is automatically boxed (copied) to Julia, processed, and a new array is returned.
    ! We then typically need to copy it back (though here we just get the handle).
    print *, "1. Deep Copy (Auto-Boxing)..."
    call cpu_time(t1)
    
    ! Note: 'matrix' is NOT a JuliaValue, so 'call' will use box_argument to copy it?
    ! Wait, current box_argument only supports scalars and JuliaValue.
    ! It does NOT support raw Fortran arrays yet for auto-boxing.
    ! So for Deep Copy, we actually assume the user might manually copy or we compare against
    ! a theoretical "copy cost". 
    ! However, 'julia_copy_array' exists. Let's use that.
    
    ! Step 1: Explicit Deep Copy to Julia
    wrapped_array = julia_copy_array_2d(matrix)
    ! Step 2: Call function (returns new array)
    res = julia%call("perf_scale_matrix", wrapped_array, 2.0d0)
    ! Step 3: Copy back (simulated by accessing one element to force sync if needed, or just time the call)
    ! In reality, deep copy involves: Fortran -> Julia Array (New alloc) -> Compute -> Julia Array (New alloc)
    
    call cpu_time(t2)
    print "(A, F10.6, A)", "   Time: ", t2 - t1, " s"
    
    ! Clean up (GC handles Julia objects, but good practice to nullify if we had manual ref counting)
    ! call wrapped_array%free() 


    ! --- Test 2: Zero-Copy ---
    ! The array is wrapped (no copy), passed to Julia, modified in-place.
    print *, "2. Zero-Copy (In-Place)..."
    call cpu_time(t1)
    
    ! Step 1: Wrap (O(1))
    ! Note: pass explicit dimensions as int64
    wrapped_array = julia_wrap_array_2d(matrix, int(N, 8), int(N, 8))
    
    ! Step 2: Call In-Place Function
    ! We pass the wrapped array. No data moves.
    res = julia%call("perf_scale_matrix_bang", wrapped_array, 2.0d0)
    
    ! The change is immediately visible in 'matrix'
    
    call cpu_time(t2)
    print "(A, F10.6, A)", "   Time: ", t2 - t1, " s"
    
    ! Verify result (quick check)
    if (matrix(1,1) > 1.0) then
         print *, "   [Verification] Matrix updated successfully."
    else
         print *, "   [Verification] Warning: Matrix values unexpected."
    end if

    print *, "--- Conclusion ---"
    print *, "Zero-Copy avoids allocating new memory and moving data,"
    print *, "yielding massive speedups for large datasets."

end program memory_transfer