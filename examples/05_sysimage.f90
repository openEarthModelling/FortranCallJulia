program ex05_sysimage
    use julia_high_level
    use julia_low_level
    use iso_c_binding
    implicit none

    type(JuliaValue) :: ctx, res, mat_obj
    character(len=256) :: img_path
    integer :: arg_len
    integer(kind=8) :: t_start, t_init, t_exec, t_rate
    real(kind=8) :: sec_init, sec_exec, sec_total
    
    real(kind=8), target :: matrix(10,10)
    type(c_ptr) :: raw_ptr, wrapped_ptr
    integer :: i

    print *, "--- Example 5: Sysimage & Startup Latency (TTFE) ---"
    
    call system_clock(count_rate=t_rate)
    
    if (command_argument_count() > 0) then
        call get_command_argument(1, img_path, arg_len)
        img_path = img_path(1:arg_len)
        print *, "[Config] Mode: Sysimage (", trim(img_path), ")"
    else
        print *, "[Config] Mode: Standard (JIT Enabled)"
    endif

    ! 1. Measure Initialization
    print *, "Step 1: Initializing Julia Runtime..."
    call system_clock(t_start)
    if (command_argument_count() > 0) then
        call julia_init_with_image(trim(img_path))
    else
        call julia_init()
    endif
    call system_clock(t_init)

    ! 2. Measure First Execution (Load Lib + Compile Inv + Exec)
    print *, "Step 2: First Execution (LinearAlgebra Inverse)..."
    
    ! Load Library (if not baked into sysimage, this still costs time)
    ! If sysimage includes ExamplesLib, this is fast.
    call julia_eval_string('include("examples_lib.jl")')
    call julia_eval_string('using .ExamplesLib')
    call julia_eval_string('const calc_inverse = ExamplesLib.calc_inverse')
    
    ! Prepare Data
    matrix = 0.0d0
    do i=1,10; matrix(i,i)=2.0d0; end do
    
    raw_ptr = c_loc(matrix)
    wrapped_ptr = fj_wrap_array_2d(raw_ptr, 10_8, 10_8)
    mat_obj%ptr = fj_retain(wrapped_ptr)

    ! Execute
    res = ctx%call_method_1_obj("calc_inverse", mat_obj)
    
    call system_clock(t_exec)

    ! 3. Report
    sec_init = real(t_init - t_start, 8) / real(t_rate, 8)
    sec_exec = real(t_exec - t_init, 8) / real(t_rate, 8)
    sec_total = sec_init + sec_exec

    print *, ""
    print *, "================================================="
    print *, "           PERFORMANCE REPORT                    "
    print *, "================================================="
    print *, " Initialization Time: ", sec_init, " s"
    print *, " First Execution Time:", sec_exec, " s (JIT+Load)"
    print *, " ------------------------------------------------"
    print *, " TOTAL STARTUP TIME : ", sec_total, " s"
    print *, "================================================="

    call julia_shutdown()

end program ex05_sysimage