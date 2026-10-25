program jit_vs_aot
    use julia_high_level
    use iso_c_binding
    implicit none

    type(JuliaValue) :: julia
#ifdef COMPILED_MODE
    ! In compiled mode, the function returns a primitive double
    real(8) :: res
#else
    ! In dynamic mode, we get a JuliaValue object
    type(JuliaValue) :: res_obj
    real(8) :: res
#endif

    real(8) :: t1, t2, t3
    character(len=256) :: sysimage_path
    logical :: use_sysimage = .false.
    integer :: arg_len

#ifdef COMPILED_MODE
    interface
        function my_add_float(x, y) bind(c, name="my_add_float")
            use iso_c_binding
            real(c_double), value :: x, y
            real(c_double) :: my_add_float
        end function
    end interface
    print *, "--- Performance: Startup & Latency (Compiled Library) ---"
#else
    print *, "--- Performance: Startup & Latency (Dynamic Call) ---"
#endif

    ! 1. Initialization
    print *, "Step 1: Initializing Julia Runtime..."
    call cpu_time(t1)
    
#ifdef COMPILED_MODE
    ! In compiled mode, the library is statically linked. 
    ! We typically still need to initialize the runtime embedded in the library.
    ! For this demo, we use the standard SDK's julia_init which works 
    ! if we are just calling functions from a shared lib that is loaded.
    call julia_init() 
#else
    if (command_argument_count() > 0) then
        call get_command_argument(1, sysimage_path, arg_len)
        sysimage_path = sysimage_path(1:arg_len)
        print *, "[Config] Loading Sysimage: ", trim(sysimage_path)
        call julia_init_with_image(trim(sysimage_path))
        use_sysimage = .true.
    else
        print *, "[Config] Default System Image (JIT Mode)"
        call julia_init()
    endif
#endif
    
    call cpu_time(t2)
    print *, "Initialization Time: ", t2 - t1, " s"

    ! 2. Load Function (Dynamic only)
#ifndef COMPILED_MODE
    if (.not. use_sysimage) then
        ! If not using sysimage, we must load the code now
        ! This simulates the "import" cost
        call julia_include_exe_relative("examples_lib.jl")
        call julia_eval_string('using .ExamplesLib')
        block
            type(JuliaValue) :: chk
            chk = julia_eval('isdefined(Main, :ExamplesLib)')
            if (.not. chk%as_logical()) error stop 'examples_lib.jl did not load: ExamplesLib undefined'
        end block
    else
        ! Even with sysimage, we need to bring the module into scope if it was compiled into it.
        ! But "include" is not needed if it was baked.
        ! We'll assume the sysimage was built with ExamplesLib.
        ! For safety in this generic test, we try "using"
        call julia_eval_string('using .ExamplesLib')
    endif
#endif

    ! 3. First Call (Cold / JIT)
    print *, "Step 2: First Execution (Cold Start)..."
    call cpu_time(t2)
#ifdef COMPILED_MODE
    res = my_add_float(10.0d0, 20.0d0)
#else
    res_obj = julia%call("perf_add_one", 10.0d0)
    res = res_obj%as_real()
#endif
    call cpu_time(t3)
    print *, "First Call Time:     ", t3 - t2, " s"
    
#ifdef COMPILED_MODE
    print *, "Result (10+20): ", res
#else
    print *, "Result (10+1):  ", res
#endif

    ! 4. Second Call (Warm)
    print *, "Step 3: Second Execution (Warm State)..."
    call cpu_time(t2)
#ifdef COMPILED_MODE
    res = my_add_float(10.0d0, 20.0d0)
#else
    res_obj = julia%call("perf_add_one", 10.0d0)
    res = res_obj%as_real()
#endif
    call cpu_time(t3)
    print *, "Steady State Time:   ", t3 - t2, " s"

    print *, "================================================="
    print *, " CONCLUSION:"
#ifdef COMPILED_MODE
    print *, " Compiled Library offers instant startup and zero"
    print *, " JIT overhead, ideal for final deployment."
#else
    if (use_sysimage) then
        print *, " Sysimage eliminates most JIT overhead, bridging"
        print *, " the gap between dynamic and compiled modes."
    else
        print *, " Standard JIT has high first-call latency."
        print *, " Use Sysimage or Compiled Lib for production."
    endif
#endif
    print *, "================================================="

    call julia_shutdown()
end program