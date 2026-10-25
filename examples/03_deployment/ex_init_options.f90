program ex_init_options
    use iso_c_binding
    use julia_high_level
    implicit none

    type(JuliaValue) :: res
    integer :: val
    integer :: nthr

    print *, "--- Example: Startup Control via julia_init_ex ---"

    ! 1. Initialize the Julia runtime with explicit startup options:
    !    - project_path: omitted on purpose -- the exe-adjacent probe finds
    !      the FortranBridge package copied next to this executable by the
    !      build, and an explicit RELATIVE path would be validated against
    !      the CWD (breaking runs from any other directory)
    !    - nthreads = 2
    !    - handle_signals = 0 ("no takeover": SIGINT/SIGTERM are reset to
    !      SIG_DFL after init; GC-critical handlers stay intact -- bridge.h)
    call julia_init_ex(nthreads=2, handle_signals=0)

    ! 2. Load your Julia Code (from next to the executable, CWD-independent)
    call julia_include_exe_relative("examples_lib.jl")
    call julia_eval_string('using .ExamplesLib')
    block
        type(JuliaValue) :: chk
        chk = julia_eval('isdefined(Main, :ExamplesLib)')
        if (.not. chk%as_logical()) error stop 'examples_lib.jl did not load: ExamplesLib undefined'
    end block

    ! 3. Evaluate a trivial expression through the existing SDK
    res = julia_eval("ExamplesLib.add_numbers(40.0, 2.0)")
    val = int(res%as_real())
    print *, "init_options: add_numbers(40, 2) = ", val

    ! 4. Confirm the startup options took effect
    res = julia_eval("Threads.nthreads()")
    nthr = res%as_integer()
    print *, "init_options: Threads.nthreads() = ", nthr

    print *, "EX_INIT_OPTIONS_OK value=", val, " nthreads=", nthr

    ! 5. Shutdown
    call julia_shutdown()

end program ex_init_options
