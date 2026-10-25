program memory_transfer
    use julia_high_level
    implicit none

    ! --- Matrix Size: 3000 x 3000 ---
    ! 3000 * 3000 * 8 bytes ~= 72 MB
    integer, parameter :: N = 3000
    real(8), allocatable :: matrix(:,:)
    type(JuliaValue) :: wrapped_array, res, julia
    real(8) :: t1, t2, v0, vlast
    integer :: i

    print *, "--- Performance Test 2: Memory Transfer (Deep Copy vs Zero-Copy) ---"
    print *, "Matrix Size: ", N, "x", N, " (approx ", real(N)*real(N)*8.0/1024.0/1024.0, " MB)"

    call julia_init()
    call julia_include_exe_relative("examples_lib.jl")
    call julia_eval_string('using .ExamplesLib')
    block
        type(JuliaValue) :: chk
        chk = julia_eval('isdefined(Main, :ExamplesLib)')
        if (.not. chk%as_logical()) error stop 'examples_lib.jl did not load: ExamplesLib undefined'
    end block

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
    
    ! Remember two elements so the in-place effect can be verified
    ! deterministically (random_number returns [0,1), so 2x lands in [0,2)).
    v0 = matrix(1, 1)
    vlast = matrix(N, N)

    ! Step 1: Wrap (O(1))
    ! Note: pass explicit dimensions as int64
    wrapped_array = julia_wrap_array_2d(matrix, int(N, 8), int(N, 8))
    
    ! Step 2: Call In-Place Function
    ! We pass the wrapped array. No data moves.
    res = julia%call("perf_scale_matrix_bang", wrapped_array, 2.0d0)
    
    ! The change is immediately visible in 'matrix'
    
    call cpu_time(t2)
    print "(A, F10.6, A)", "   Time: ", t2 - t1, " s"
    
    ! Deterministic check: in-place scaling must exactly double the two
    ! sampled elements. (The old check, matrix(1,1) > 1.0, was a coin flip
    ! on the random draw: it "warned" on roughly half of the CORRECT runs,
    ! since 2*x for x in [0,1) exceeds 1.0 only when x > 0.5.)
    if (abs(matrix(1,1) - 2.0d0*v0) <= 1.0d-12 * max(abs(v0), 1.0d-300) .and. &
        abs(matrix(N,N) - 2.0d0*vlast) <= 1.0d-12 * max(abs(vlast), 1.0d-300)) then
         print *, "   [Verification] Matrix updated successfully (elements (1,1) and (N,N) exactly doubled)."
    else
         print *, "   [Verification] FAILED: matrix(1,1)=", matrix(1,1), &
              " expected ", 2.0d0*v0, "; matrix(N,N)=", matrix(N,N), " expected ", 2.0d0*vlast
         error stop 1
    end if

    print *, "--- Conclusion ---"
    print *, "Zero-Copy avoids allocating new memory and moving data,"
    print *, "yielding massive speedups for large datasets."

end program memory_transfer